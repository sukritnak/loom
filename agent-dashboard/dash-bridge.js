#!/usr/bin/env node
/*
 * dash-bridge.js — universal hook bridge → Loom central dashboard.
 * Claude Code (~/.claude/settings.json) · Cursor (~/.cursor/hooks.json) · Hermes (shell hooks in config.yaml).
 *
 * Usage: node dash-bridge.js [eventHint]
 *   eventHint optional when hook_event_name is missing (Cursor afterAgentResponse).
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { cleanProject, resolveProject, resolveControlDir, resolveDisplayPath } = require(path.join(__dirname, '../tools/resolve-project.js'));
const { cmdLabel } = require('./capability-labels');

const IDS = new Set(['orch', 'pm', 'design', 'be', 'besr', 'fe', 'feanim', 'qa']);
const AGENT_MAP = {
  be: 'be', 'be-sr': 'besr', besr: 'besr', 'backend-agent': 'be', 'backend-senior-agent': 'besr',
  fe: 'fe', 'fe-anim': 'feanim', feanim: 'feanim', 'frontend-agent': 'fe', 'frontend-animation-agent': 'feanim',
  qa: 'qa', 'qa-agent': 'qa', pm: 'pm', 'pm-agent': 'pm',
  design: 'design', 'designer-agent': 'design',
  'loop-orch': 'orch', orch: 'orch', 'tech-loop-orchestrator': 'orch', 'loop-start': 'orch',
  explore: 'orch', shell: 'orch', generalpurpose: 'orch',
};
const STATE_DIR = path.join(os.homedir(), '.loop-dash');
const DEDUPE_MS = 4000;
const FILE_COALESCE_MS = 20000; // merge rapid edits to same file into one log line
const FILE_DETAIL_CAP = 8000;

/** Full changed text for activity feed (all lines, not first-line preview). */
function fileEditDetail(...parts) {
  return parts
    .flatMap(p => (Array.isArray(p) ? p : [p]))
    .map(s => String(s || '').trimEnd())
    .filter(s => s.trim())
    .join('\n')
    .trim();
}

/** Split long edit text into multiple log chunks (never truncate). */
function splitDetail(text) {
  const t = String(text || '').trim();
  if (!t) return [];
  if (t.length <= FILE_DETAIL_CAP) return [t];
  const chunks = [];
  let rest = t;
  while (rest.length > FILE_DETAIL_CAP) {
    let cut = rest.lastIndexOf('\n', FILE_DETAIL_CAP);
    if (cut < FILE_DETAIL_CAP * 0.4) cut = FILE_DETAIL_CAP;
    chunks.push(rest.slice(0, cut).trimEnd());
    rest = rest.slice(cut).trimStart();
  }
  if (rest) chunks.push(rest);
  return chunks;
}

function splitEditPair(removed, added) {
  const rParts = removed ? splitDetail(removed) : [];
  const aParts = added ? splitDetail(added) : [];
  const n = Math.max(rParts.length, aParts.length, 1);
  const chunks = [];
  for (let i = 0; i < n; i++) {
    chunks.push({ removed: rParts[i] || '', added: aParts[i] || '' });
  }
  return chunks;
}

function pushFileDash(who, action, displayFp, chunk, project, controlDir, opts = {}) {
  const base = path.basename(String(displayFp).split('→')[0].trim());
  const verb = action === 'create' ? 'สร้าง' : action === 'delete' ? 'ลบ' : 'แก้';
  const suffix = opts.suffix || '';
  const tmp = path.join(STATE_DIR, `edit-${Date.now()}-${process.pid}.json`);
  fs.writeFileSync(tmp, JSON.stringify({ removed: chunk.removed || '', added: chunk.added || '' }));
  const args = opts.append
    ? ['file-append', who, displayFp, `@${tmp}`]
    : ['file', who, action, displayFp, `@${tmp}`];
  args.push(`speech=${verb} ${base}${suffix}`);
  if (suffix) args.push(`activity=${verb} ${base}${suffix}`);
  const lm = opts.lineMeta || {};
  if (lm.lines) args.push(`lines=${lm.lines}`);
  if (lm.lineStart) args.push(`lineStart=${lm.lineStart}`);
  if (lm.lineEnd) args.push(`lineEnd=${lm.lineEnd}`);
  if (lm.removedLineStart) args.push(`removedLineStart=${lm.removedLineStart}`);
  if (lm.addedLineStart) args.push(`addedLineStart=${lm.addedLineStart}`);
  dash(args, project, controlDir);
  try { fs.unlinkSync(tmp); } catch (e) { /* ok */ }
}
/** Internal / debug shell — never show on the activity board. */
const SKIP_SHELL_RES = [
  /agent-status\.js|dash\.sh|dash-bridge|cc-dash-bridge|resolve-project\.js/i,
  /status\.json/i,
  /\bnode\s+-e\b/,
  /\bgit\s+(status|diff|log)\b/i,
  /\b(rg|grep|cat|head|tail|wc|ls|pwd|echo)\b/i,
];
/** Loom dashboard hook plumbing — edits here aren't user-project work. */
const SKIP_FILE_RES = [
  /(^|\/)agent-dashboard\/(dash-bridge|agent-status|cc-dash-bridge)\.js$/,
  /(^|\/)agent-dashboard\/status\.json$/,
  /(^|\/)tools\/(dash\.sh|resolve-project\.js|install-(dash|cursor|cc|hermes)-hooks\.sh)$/,
  /(^|\/)log-archive\//,
];
const EVENT_HINT = (process.argv[2] || '').trim();

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch (e) { return ''; }
}

function baseDir() {
  try {
    const p = path.join(os.homedir(), '.loop-base');
    const b = fs.readFileSync(p, 'utf8').trim();
    if (b && fs.existsSync(path.join(b, 'agent-dashboard/agent-status.js'))) return b;
  } catch (e) { /* ponytail: fall through */ }
  return path.join(__dirname, '..');
}

function resolveCwd(input) {
  if (input.cwd) return input.cwd;
  if (Array.isArray(input.workspace_roots) && input.workspace_roots[0]) return input.workspace_roots[0];
  if (process.env.CURSOR_CWD) return process.env.CURSOR_CWD;
  return process.cwd();
}

function findControl(cwd) {
  const dir = resolveControlDir(cwd);
  const project = resolveProject(cwd);
  return { dir, project };
}

function mapWho(agentType) {
  if (!agentType) return 'orch';
  const k = String(agentType).toLowerCase().replace(/_/g, '-');
  if (IDS.has(k)) return k;
  return AGENT_MAP[k] || AGENT_MAP[k.replace(/-/g, '')] || 'orch';
}

function isHermes(input) {
  const e = String(input.hook_event_name || '');
  return e.includes('_'); // post_tool_call, subagent_stop, …
}

function hermesOk() {
  process.stdout.write('{}\n');
}

function exitBridge(input) {
  if (isHermes(input)) hermesOk();
  process.exit(0);
}

function extra(input) {
  return input.extra && typeof input.extra === 'object' ? input.extra : {};
}

function normalizeEvent(input) {
  const raw = input.hook_event_name || EVENT_HINT || '';
  const e = String(raw).toLowerCase();
  const map = {
    subagentstart: 'subagentStart',
    posttooluse: 'postToolUse',
    post_tool_call: 'postToolUse',
    subagentstop: 'subagentStop',
    subagent_stop: 'subagentStop',
    subagent_start: 'subagentStart',
    post_llm_call: 'afterAgentResponse',
    afteragentresponse: 'afterAgentResponse',
    afterfileedit: 'afterFileEdit',
    aftertabfileedit: 'afterFileEdit',
    aftershellexecution: 'afterShellExecution',
    stop: 'stop',
  };
  if (map[e]) return map[e];
  // Claude Code PascalCase
  if (raw === 'SubagentStart') return 'subagentStart';
  if (raw === 'PostToolUse') return 'postToolUse';
  if (raw === 'SubagentStop') return 'subagentStop';
  if (raw === 'Stop') return 'stop';
  if (EVENT_HINT) return EVENT_HINT;
  if (input.subagent_type && input.summary !== undefined) return 'subagentStop';
  if (input.subagent_type && input.task !== undefined && input.summary === undefined) return 'subagentStart';
  if (input.text && !input.tool_name) return 'afterAgentResponse';
  if (input.file_path && input.edits) return 'afterFileEdit';
  if (input.command && input.cwd && !input.tool_name) return 'afterShellExecution';
  if (input.tool_name) return 'postToolUse';
  return '';
}

function sessionId(input) {
  return input.session_id || input.conversation_id || input.parent_conversation_id || 'default';
}

function statePath(sid) {
  return path.join(STATE_DIR, `${sid || 'default'}.json`);
}

function loadState(sid) {
  try { return JSON.parse(fs.readFileSync(statePath(sid), 'utf8')); } catch (e) {
    return { who: 'orch', reports: {}, lastReportAt: 0 };
  }
}

function saveState(sid, st) {
  try {
    fs.mkdirSync(STATE_DIR, { recursive: true });
    fs.writeFileSync(statePath(sid), JSON.stringify(st, null, 2));
  } catch (e) { /* best effort */ }
}

function normPath(fp) {
  return String(fp || '').replace(/\\/g, '/');
}

function shouldSkipShell(cmd) {
  const c = String(cmd || '').trim();
  if (!c) return true;
  return SKIP_SHELL_RES.some(re => re.test(c));
}

function shouldSkipFile(fp) {
  const n = normPath(fp);
  if (!n) return true;
  return SKIP_FILE_RES.some(re => re.test(n));
}

function cleanDetail(detail) {
  const d = String(detail || '').trim();
  if (!d || /^#!/.test(d)) return '';
  if (/^(import |const .*require|\/\/|\/\*)/.test(d) && d.length < 100) return '';
  return d;
}

/** File diff text — keep all lines (imports/comments are valid diff content). */
function editText(raw) {
  const t = String(raw || '').trimEnd();
  if (!t.trim()) return '';
  if (/^#!/.test(t.trim())) return '';
  return t.trim();
}

function pickField(obj, keys) {
  if (!obj || typeof obj !== 'object') return '';
  for (const k of keys) {
    if (obj[k] != null && String(obj[k]).length) return String(obj[k]);
  }
  return '';
}

function toolInput(input) {
  const ex = extra(input);
  return input.tool_input || input.toolInput || input.input || input.arguments
    || ex.tool_input || ex.toolInput || {};
}

function filePathFrom(ti, cwd) {
  const raw = pickField(ti, ['path', 'file_path', 'filePath', 'target', 'file']);
  return relPath(raw, cwd);
}

function editPairFrom(ti) {
  return {
    removed: editText(pickField(ti, ['old_string', 'oldString', 'old_str', 'oldStr', 'search', 'find', 'before'])),
    added: editText(pickField(ti, ['new_string', 'newString', 'new_str', 'newStr', 'replace', 'content', 'text', 'body', 'after', 'patch'])),
  };
}

function parseLineNum(v) {
  const n = parseInt(String(v ?? ''), 10);
  return Number.isFinite(n) && n > 0 ? n : null;
}

function lineRangeFromEdit(e) {
  if (!e || typeof e !== 'object') return null;
  const r = e.range || e.line_range || e.lineRange || {};
  const start = parseLineNum(pickField(r, ['start_line_number', 'startLineNumber', 'start_line', 'startLine']))
    ?? parseLineNum(pickField(e, ['start_line_number', 'startLineNumber', 'start_line', 'startLine', 'line', 'line_number']));
  let end = parseLineNum(pickField(r, ['end_line_number', 'endLineNumber', 'end_line', 'endLine']))
    ?? parseLineNum(pickField(e, ['end_line_number', 'endLineNumber', 'end_line', 'endLine']));
  if (!start) return null;
  if (!end) end = start;
  return { start, end };
}

function lineFromContent(content, snippet) {
  const lines = String(snippet || '').split('\n');
  for (const raw of lines) {
    const needle = raw.trimEnd();
    if (!needle.trim()) continue;
    const idx = content.indexOf(needle);
    if (idx >= 0) return content.slice(0, idx).split('\n').length;
  }
  return null;
}

function absFilePath(fp, cwd) {
  if (!fp) return '';
  try {
    return path.isAbsolute(fp) ? fp : path.resolve(cwd || process.cwd(), fp);
  } catch (e) { return fp; }
}

/** Line gutter for diff UI — hook range when present, else locate added text in file on disk. */
function lineMetaForEdit(edits, ti, fp, cwd, removed, added) {
  const editList = Array.isArray(edits) ? edits : [];
  let start = null;
  let end = null;
  for (const e of editList) {
    const range = lineRangeFromEdit(e);
    if (!range) continue;
    if (start == null || range.start < start) start = range.start;
    if (end == null || range.end > end) end = range.end;
  }
  if (start == null && ti) {
    start = parseLineNum(pickField(ti, ['start_line', 'startLine', 'line', 'line_number', 'start_line_number']));
    end = parseLineNum(pickField(ti, ['end_line', 'endLine', 'end_line_number'])) || start;
  }
  const addedText = added || '';
  const removedText = removed || '';
  if (start == null && addedText) {
    try {
      const abs = absFilePath(fp, cwd);
      const content = fs.readFileSync(abs, 'utf8');
      const ln = lineFromContent(content, addedText);
      if (ln) {
        start = ln;
        end = ln + Math.max(0, addedText.split('\n').length - 1);
      }
    } catch (e) { /* ok */ }
  }
  if (start == null) return {};
  if (!end) {
    const span = Math.max(addedText.split('\n').length, removedText.split('\n').length, 1);
    end = start + span - 1;
  }
  const rangeLabel = end > start ? `L${start}–${end}` : `L${start}`;
  return {
    lineStart: String(start),
    lineEnd: String(end),
    removedLineStart: String(start),
    addedLineStart: String(start),
    lines: rangeLabel,
  };
}

function editsFromAfterFileEdit(input) {
  const edits = Array.isArray(input.edits) ? input.edits : [];
  if (edits.length) {
    return {
      removed: fileEditDetail(edits.map((e) => pickField(e, ['old_string', 'oldString', 'old_str', 'oldStr', 'before']))),
      added: fileEditDetail(edits.map((e) => pickField(e, ['new_string', 'newString', 'new_str', 'newStr', 'after']))),
      edits,
    };
  }
  const pair = editPairFrom(input);
  return { ...pair, edits: [] };
}

function recentKey(st, bucket, key) {
  st[bucket] = st[bucket] || {};
  const now = Date.now();
  const last = st[bucket][key];
  if (last && now - last < DEDUPE_MS) return true;
  st[bucket][key] = now;
  const keys = Object.keys(st[bucket]);
  if (keys.length > 60) {
    for (const k of keys.slice(0, keys.length - 60)) delete st[bucket][k];
  }
  return false;
}

function touchFileEdit(st, key) {
  st.recentFiles = st.recentFiles || {};
  st.recentFiles[key] = Date.now();
  const keys = Object.keys(st.recentFiles);
  if (keys.length > 60) {
    for (const k of keys.slice(0, keys.length - 60)) delete st.recentFiles[k];
  }
}

function fileEditCoalesce(st, key) {
  st.recentFiles = st.recentFiles || {};
  const last = st.recentFiles[key];
  return last && Date.now() - last < FILE_COALESCE_MS;
}

function relPath(abs, cwd) {
  if (!abs) return '';
  try {
    const r = path.relative(cwd, abs);
    return r.startsWith('..') ? abs : r;
  } catch (e) { return abs; }
}

function dash(argv, project, controlDir) {
  const B = baseDir();
  const script = path.join(B, 'agent-dashboard/agent-status.js');
  if (!fs.existsSync(script)) return;
  const env = { ...process.env };
  const p = cleanProject(project || process.env.LOOP_PROJECT);
  if (p) env.LOOP_PROJECT = p;
  else delete env.LOOP_PROJECT;
  if (controlDir) env.LOOP_CONTROL_DIR = controlDir;
  spawnSync(process.execPath, [script, ...argv], {
    env,
    cwd: controlDir,
    stdio: 'ignore',
  });
}

function cursorOk() {
  process.stdout.write(`${JSON.stringify({ additional_context: '' })}\n`);
}

function reportMessage(st, sid, who, msg, project, controlDir) {
  const body = String(msg || '').trim();
  if (!body || body.length < 40) return false;
  const key = `${who}:${body.slice(0, 200)}`;
  st.reports = st.reports || {};
  if (st.reports[key]) return false;
  st.reports[key] = Date.now();
  const keys = Object.keys(st.reports);
  if (keys.length > 40) {
    for (const k of keys.slice(0, keys.length - 40)) delete st.reports[k];
  }
  st.lastReportAt = Date.now();
  saveState(sid, st);

  const title = body.split('\n').find(l => l.trim())?.trim().slice(0, 140) || `${who} update`;
  const speech = title.slice(0, 200);
  const tmp = path.join(STATE_DIR, `report-${Date.now()}.txt`);
  fs.writeFileSync(tmp, body);
  dash(['report', who, `title=${title}`, `speech=${speech}`, `@${tmp}`], project, controlDir);
  try { fs.unlinkSync(tmp); } catch (e) { /* ok */ }

  const state = /FAIL|fail|error|blocked/i.test(body) ? 'fix' : 'done';
  dash(['set', who, state, title.slice(0, 80), title.slice(0, 80), `speech=${speech}`], project, controlDir);
  return true;
}

function handleFile(who, action, fp, edit, project, controlDir, st, sid, cwd, opts = {}) {
  if (!fp || shouldSkipFile(fp)) return;
  const displayFp = resolveDisplayPath(fp, controlDir, cwd || controlDir);
  const removed = editText(edit && edit.removed);
  const added = editText(edit && edit.added);
  if (!removed && !added && action !== 'delete') return;
  const lineMeta = opts.lineMeta || lineMetaForEdit(opts.edits, opts.ti, fp, cwd, removed, added);
  const chunks = splitEditPair(removed, added);
  const key = `${who}:${action}:${normPath(fp)}`;
  const coalesce = fileEditCoalesce(st, key);
  touchFileEdit(st, key);
  saveState(sid, st);
  chunks.forEach((chunk, i) => {
    const merge = coalesce || i > 0;
    const suffix = !merge && chunks.length > 1 ? ` (${i + 1}/${chunks.length})` : '';
    pushFileDash(who, action, displayFp, chunk, project, controlDir, {
      append: merge,
      suffix,
      lineMeta: i === 0 ? lineMeta : {},
    });
  });
}

function handleShell(who, cmd, project, controlDir, st, sid) {
  if (shouldSkipShell(cmd)) return;
  const label = cmdLabel(cmd);
  if (!label) return; // ponytail: raw shell commands confuse users — only known labels
  const key = `${who}:${String(cmd).slice(0, 300)}`;
  if (recentKey(st, 'recentCmds', key)) return;
  saveState(sid, st);
  dash(['cmd', who, label, `activity=${label}`, `speech=${label}`], project, controlDir);
}

function main() {
  let input;
  try { input = JSON.parse(readStdin() || '{}'); } catch (e) { process.exit(0); }

  const event = normalizeEvent(input);
  if (!event) process.exit(0);

  const sid = sessionId(input);
  const cwd = resolveCwd(input);
  const { dir: controlDir, project } = findControl(cwd);
  const st = loadState(sid);

  if (event === 'subagentStart') {
    const ex = extra(input);
    const who = mapWho(ex.child_role || input.agent_type || input.subagent_type);
    st.who = who;
    st.agent_type = ex.child_role || input.agent_type || input.subagent_type || '';
    st.cwd = cwd;
    saveState(sid, st);
    const label = (ex.child_goal || input.task || input.agent_type || input.subagent_type || who).slice(0, 80);
    dash(['set', who, 'work', label, `subagent started: ${label}`, `speech=เริ่มงาน: ${label}`], project, controlDir);
    exitBridge(input);
  }

  const who = st.who || mapWho(extra(input).child_role || input.agent_type || input.subagent_type) || 'orch';

  if (event === 'postToolUse') {
    const tool = String(input.tool_name || input.tool || '').trim();
    const ti = toolInput(input);
    if (tool === 'Write' || tool === 'Edit') {
      const fp = filePathFrom(ti, cwd);
      const pair = tool === 'Write'
        ? { removed: '', added: editText(pickField(ti, ['content', 'new_string', 'newString', 'text', 'body'])) }
        : editPairFrom(ti);
      handleFile(who, tool === 'Write' ? 'create' : 'edit', fp, pair, project, controlDir, st, sid, cwd, { ti });
    } else if (tool === 'StrReplace' || tool === 'search_replace') {
      const fp = filePathFrom(ti, cwd);
      const pair = editPairFrom(ti);
      handleFile(who, 'edit', fp, pair, project, controlDir, st, sid, cwd, { ti });
    } else if (tool === 'Delete') {
      const fp = filePathFrom(ti, cwd);
      handleFile(who, 'delete', fp, {}, project, controlDir, st, sid, cwd, { ti });
    } else if (tool === 'write_file') {
      const fp = filePathFrom(ti, cwd);
      handleFile(who, 'create', fp, { removed: '', added: editText(pickField(ti, ['content', 'text', 'body'])) }, project, controlDir, st, sid, cwd, { ti });
    } else if (tool === 'patch') {
      const fp = filePathFrom(ti, cwd);
      handleFile(who, 'edit', fp, editPairFrom(ti), project, controlDir, st, sid, cwd, { ti });
    } else if (tool === 'Shell' || tool === 'Bash' || tool === 'terminal') {
      handleShell(who, ti.command || pickField(ti, ['command', 'cmd']) || '', project, controlDir, st, sid);
    }
    exitBridge(input);
  }

  if (event === 'afterFileEdit') {
    const fp = relPath(input.file_path || input.filePath || '', cwd);
    const bundle = editsFromAfterFileEdit(input);
    handleFile(who, 'edit', fp, bundle, project, controlDir, st, sid, cwd, { edits: bundle.edits, ti: input });
    exitBridge(input);
  }

  if (event === 'afterShellExecution') {
    handleShell(who, input.command || '', project, controlDir, st, sid);
    exitBridge(input);
  }

  if (event === 'subagentStop') {
    const ex = extra(input);
    const id = mapWho(ex.child_role || input.agent_type || input.subagent_type || st.agent_type || st.who);
    let msg = String(ex.child_summary || input.summary || input.last_assistant_message || '').trim();
    if (!msg && input.agent_transcript_path && fs.existsSync(input.agent_transcript_path)) {
      try {
        const tail = fs.readFileSync(input.agent_transcript_path, 'utf8').slice(-12000);
        msg = tail.split('\n').slice(-80).join('\n').trim();
      } catch (e) { /* ok */ }
    }
    reportMessage(st, sid, id, msg, project, controlDir);
    exitBridge(input);
  }

  if (event === 'afterAgentResponse') {
    const ex = extra(input);
    reportMessage(st, sid, 'orch', input.text || ex.assistant_response || '', project, controlDir);
    if (isHermes(input)) hermesOk();
    else cursorOk();
    process.exit(0);
  }

  if (event === 'stop') {
    const msg = String(input.last_assistant_message || '').trim();
    const recent = st.lastReportAt && (Date.now() - st.lastReportAt < 8000);
    if (!recent && msg) reportMessage(st, sid, 'orch', msg, project, controlDir);
    exitBridge(input);
  }

  exitBridge(input);
}

if (process.argv.includes('--self-check')) {
  console.assert(shouldSkipShell('node -e "require(\'status.json\')"'), 'skip node -e');
  console.assert(shouldSkipShell('cd /tmp && node resolve-project.js'), 'skip resolve');
  console.assert(shouldSkipFile('agent-dashboard/dash-bridge.js'), 'skip dash-bridge file');
  console.assert(cleanDetail('#!/usr/bin/env node') === '', 'strip shebang');
  console.assert(!shouldSkipShell('npm test'), 'keep npm test');
  console.assert(normalizeEvent({ hook_event_name: 'post_tool_call' }) === 'postToolUse', 'hermes post_tool_call');
  console.assert(normalizeEvent({ hook_event_name: 'subagent_stop' }) === 'subagentStop', 'hermes subagent_stop');
  console.assert(cmdLabel('npm test'), 'label npm test');
  console.assert(splitDetail('x'.repeat(9000)).length >= 2, 'split long detail');
  console.assert(resolveDisplayPath('/tmp/proj/src/a.ts', '/tmp/proj') === 'src/a.ts', 'display path rel');
  console.assert(editText('import { x } from "y";').includes('import'), 'keep import in diff');
  console.assert(editPairFrom({ old_string: 'a', new_string: 'b' }).added === 'b', 'edit pair');
  console.assert(editPairFrom({ oldString: 'a', newString: 'b' }).removed === 'a', 'camelCase edit pair');
  console.assert(lineRangeFromEdit({ range: { start_line_number: 57, end_line_number: 63 } }).start === 57, 'cursor tab range');
  console.log('dash-bridge self-check ok');
  process.exit(0);
}

main();
