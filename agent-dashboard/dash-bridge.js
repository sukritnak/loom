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
const { cleanProject, resolveDisplayPath, serviceRoots } = require(path.join(__dirname, '../tools/resolve-project.js'));
const { cmdLabel } = require('./capability-labels');

const IDS = new Set(['orch', 'pm', 'ux-ui', 'be', 'fullstack', 'fe', 'fe-mo', 'qa']);
const LOOM_AGENTS = new Set([
  'loom-start', 'loom-orch', 'loom-orchestrator', 'orch',
  'loom-pm', 'pm', 'pm-agent', 'loom-ux-ui', 'ux-ui', 'ux-ui-agent',
  'loom-be', 'be', 'loom-full-stack', 'fullstack', 'backend-agent', 'fullstack-agent',
  'loom-fe', 'fe', 'loom-motion', 'fe-mo', 'frontend-agent', 'fe-mo-agent',
  'loom-qa', 'qa', 'qa-agent',
]);
const LOOM_INVOKE_RE = /\b(?:use\s+)?loom(?:-(?:start|orch|pm|ux-ui|fe|motion|be|full-stack|qa))?\b|\buse\s+loom\s+(?:pm|ux-ui|fe|motion|be|full-stack|qa)\b|\/(?:loom-(?:start|orch|pm|ux-ui|fe|motion|be|full-stack|qa))\b/i;
const AGENT_MAP = {
  be: 'be', 'loom-be': 'be', 'backend-agent': 'be',
  'loom-full-stack': 'fullstack', fullstack: 'fullstack', 'be-sr': 'fullstack', besr: 'fullstack', 'backend-senior-agent': 'fullstack', 'fullstack-agent': 'fullstack',
  fe: 'fe', 'loom-fe': 'fe', 'frontend-agent': 'fe',
  'loom-motion': 'fe-mo', 'fe-mo': 'fe-mo', 'fe-anim': 'fe-mo', feanim: 'fe-mo', 'frontend-animation-agent': 'fe-mo', 'fe-mo-agent': 'fe-mo',
  qa: 'qa', 'loom-qa': 'qa', 'qa-agent': 'qa',
  pm: 'pm', 'loom-pm': 'pm', 'pm-agent': 'pm',
  'loom-ux-ui': 'ux-ui', 'ux-ui': 'ux-ui', design: 'ux-ui', 'designer-agent': 'ux-ui', 'ux-ui-agent': 'ux-ui',
  'loom-orch': 'orch', orch: 'orch', 'loom-orchestrator': 'orch', 'tech-loop-orchestrator': 'orch',
  'loom-start': 'orch',
};
const STATE_DIR = path.join(os.homedir(), '.loop-dash');
const GLOBAL_STATE = path.join(STATE_DIR, 'global.json');
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
  /\b(rg|grep|cat|head|tail|wc|ls|pwd|echo|find|fd)\b/i,
  /\bcd\s+[^\s&|]+\s*&&\s*(cat|head|rg|grep)\b/i,
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

function loopBase() {
  try {
    const b = fs.readFileSync(path.join(os.homedir(), '.loop-base'), 'utf8').trim();
    if (b && fs.existsSync(b)) return b;
  } catch (e) { /* ok */ }
  return '';
}

function readProjectFromDir(dir) {
  try {
    const raw = fs.readFileSync(path.join(dir, 'loop.config.json'), 'utf8');
    return cleanProject(JSON.parse(raw).project);
  } catch (e) {
    return '';
  }
}

function hookDebug(msg, data) {
  if (process.env.LOOM_DASH_DEBUG !== '1') return;
  try {
    fs.mkdirSync(STATE_DIR, { recursive: true });
    const line = `${new Date().toISOString()} ${msg}${data ? ' ' + JSON.stringify(data) : ''}\n`;
    fs.appendFileSync(path.join(STATE_DIR, 'hook-debug.log'), line);
  } catch (e) { /* ok */ }
}

function activeControlDir() {
  const base = loopBase();
  if (!base) return '';
  try {
    const active = fs.readFileSync(path.join(base, '.active-project'), 'utf8').trim();
    if (active && fs.existsSync(path.join(active, 'loop.config.json'))) return active;
  } catch (e) { /* ok */ }
  return '';
}

/** Blueprint, control folder, or any service path from the active job. */
function isLoomJobWorkspace(cwd) {
  const r = path.resolve(cwd || process.cwd());
  const base = loopBase();
  const active = activeControlDir();
  const roots = new Set();
  if (base) roots.add(path.resolve(base));
  if (active) {
    roots.add(path.resolve(active));
    for (const p of serviceRoots(active)) roots.add(path.resolve(p));
  }
  for (const root of roots) {
    if (r === root || r.startsWith(root + path.sep)) return true;
  }
  return false;
}

function loadGlobal() {
  try { return JSON.parse(fs.readFileSync(GLOBAL_STATE, 'utf8')); } catch (e) {
    return { loomActive: false };
  }
}

function saveGlobal(patch) {
  try {
    fs.mkdirSync(STATE_DIR, { recursive: true });
    const g = { ...loadGlobal(), ...patch, at: Date.now() };
    fs.writeFileSync(GLOBAL_STATE, JSON.stringify(g, null, 2));
  } catch (e) { /* ok */ }
}

function mergeGlobalActivation(st, input, sid) {
  const g = loadGlobal();
  if (!g.loomActive) return;
  const cid = input.parent_conversation_id || input.conversation_id || sid;
  const fresh = !g.at || (Date.now() - g.at < 7 * 24 * 3600 * 1000);
  const sameConvo = g.conversation_id && (g.conversation_id === cid || g.conversation_id === sid);
  if (sameConvo || (fresh && isLoomJobWorkspace(resolveCwd(input)))) {
    st.loomActive = true;
    if (g.who) st.who = g.who;
  }
}

/** Hooks: cwd walk; .active-project when session active or workspace is the active Loom job. */
function resolveHookContext(cwd, loomActive) {
  let d = path.resolve(cwd || process.cwd());
  for (let i = 0; i < 16 && d && d !== path.dirname(d); i++) {
    if (fs.existsSync(path.join(d, 'loop.config.json'))) {
      return { controlDir: d, project: readProjectFromDir(d) };
    }
    d = path.dirname(d);
  }
  const active = activeControlDir();
  if (!active) return { controlDir: null, project: '' };
  if (loomActive || isLoomJobWorkspace(cwd)) {
    return { controlDir: active, project: readProjectFromDir(active) };
  }
  return { controlDir: null, project: '' };
}

function normAgentKey(v) {
  return String(v || '').toLowerCase().replace(/_/g, '-');
}

function isLoomAgentType(agentType) {
  const k = normAgentKey(agentType);
  return LOOM_AGENTS.has(k);
}

function promptText(input) {
  const ex = extra(input);
  return pickField(input, ['prompt', 'user_message', 'userMessage', 'user_prompt', 'userPrompt', 'message', 'content'])
    || pickField(ex, ['user_message', 'userMessage', 'user_prompt', 'userPrompt', 'prompt', 'message', 'content']);
}

function maybeActivateLoom(st, input, event) {
  if (st.loomActive) return true;
  if (process.env.LOOM_DASH_ACTIVE === '1') {
    st.loomActive = true;
    const at = input.agent_type || process.env.LOOM_DASH_AGENT || '';
    if (isLoomAgentType(at)) st.who = mapWho(at);
    return true;
  }
  if (isLoomJobWorkspace(resolveCwd(input))) {
    st.loomActive = true;
    return true;
  }
  if (event === 'sessionStart' && isLoomAgentType(input.agent_type)) {
    st.loomActive = true;
    st.who = mapWho(input.agent_type);
    return true;
  }
  if ((event === 'beforeSubmitPrompt' || event === 'preLlmCall') && LOOM_INVOKE_RE.test(promptText(input))) {
    st.loomActive = true;
    return true;
  }
  if (event === 'subagentStart') {
    const agent = hookAgentType(input);
    if (isLoomAgentType(agent)) {
      st.loomActive = true;
      return true;
    }
  }
  if (event === 'postToolUse') {
    const tool = String(input.tool_name || input.tool || '').trim();
    if (tool === 'Task') {
      const ti = toolInput(input);
      if (isLoomAgentType(ti.subagent_type || ti.agent_type)) {
        st.loomActive = true;
        return true;
      }
    }
  }
  return false;
}

function hookAgentType(input) {
  const ex = extra(input);
  const ti = toolInput(input);
  return pickField(input, ['agent_type', 'subagent_type', 'subagentType', 'child_role', 'childRole'])
    || pickField(ex, ['child_role', 'childRole', 'agent_type', 'subagent_type', 'child_agent'])
    || pickField(ti, ['subagent_type', 'subagentType', 'agent_type']);
}

function hookAgentId(input) {
  const ex = extra(input);
  return pickField(input, ['agent_id', 'subagent_id', 'agentId', 'subagentId', 'tool_call_id'])
    || pickField(ex, ['child_id', 'agent_id', 'subagent_id']);
}

function registerSubagent(st, input) {
  const at = hookAgentType(input);
  if (!at) return st.who || 'orch';
  const who = mapWho(at);
  st.who = who;
  st.agent_type = at;
  const aid = hookAgentId(input) || at;
  st.subagents = st.subagents || {};
  st.subagents[aid] = who;
  st.activeSubagent = aid;
  return who;
}

/** CC agent_type · Cursor subagent_id registry · Hermes extra.child_role */
function resolveWho(st, input) {
  const aid = hookAgentId(input);
  if (aid && st.subagents?.[aid]) {
    st.who = st.subagents[aid];
    return st.who;
  }
  const at = hookAgentType(input);
  if (at) {
    st.who = mapWho(at);
    st.agent_type = at;
    if (aid) {
      st.subagents = st.subagents || {};
      st.subagents[aid] = st.who;
      st.activeSubagent = aid;
    }
    return st.who;
  }
  if (st.activeSubagent && st.subagents?.[st.activeSubagent]) {
    st.who = st.subagents[st.activeSubagent];
  }
  return st.who || 'orch';
}

function clearSubagent(st, input) {
  const aid = hookAgentId(input) || st.activeSubagent;
  if (aid && st.subagents) delete st.subagents[aid];
  if (st.activeSubagent === aid) delete st.activeSubagent;
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
    pre_llm_call: 'preLlmCall',
    on_session_start: 'sessionStart',
    post_llm_call: 'afterAgentResponse',
    beforesubmitprompt: 'beforeSubmitPrompt',
    userpromptsubmit: 'beforeSubmitPrompt',
    afteragentresponse: 'afterAgentResponse',
    afterfileedit: 'afterFileEdit',
    aftertabfileedit: 'afterFileEdit',
    aftershellexecution: 'afterShellExecution',
    stop: 'stop',
  };
  if (map[e]) return map[e];
  // Claude Code PascalCase
  if (raw === 'SessionStart') return 'sessionStart';
  if (raw === 'UserPromptSubmit') return 'beforeSubmitPrompt';
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
  return input.conversation_id || input.session_id || input.parent_conversation_id || 'default';
}

/** Cursor subagent hooks use parent_conversation_id — share one state file with parent. */
function stateSessionId(input) {
  return input.parent_conversation_id || input.conversation_id || input.session_id || 'default';
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

  const sid = stateSessionId(input);
  const cwd = resolveCwd(input);
  const st = loadState(sid);
  mergeGlobalActivation(st, input, sid);
  const activated = maybeActivateLoom(st, input, event);
  if (activated) {
    saveState(sid, st);
    saveGlobal({ loomActive: true, conversation_id: stateSessionId(input), who: st.who || 'orch' });
  }
  hookDebug(event, { sid, activated, loomActive: st.loomActive, cwd: cwd.slice(-60) });

  if (event === 'beforeSubmitPrompt' || event === 'sessionStart' || event === 'preLlmCall') {
    if (isHermes(input)) hermesOk();
    else cursorOk();
    process.exit(0);
  }

  if (!st.loomActive) {
    hookDebug('skip-inactive', { sid, event });
    exitBridge(input);
  }

  const { controlDir, project } = resolveHookContext(cwd, st.loomActive);
  if (!controlDir) {
    hookDebug('skip-no-control', { sid, event, cwd });
    exitBridge(input);
  }

  if (event === 'subagentStart') {
    const who = registerSubagent(st, input);
    st.cwd = cwd;
    saveState(sid, st);
    const label = (extra(input).child_goal || input.task || hookAgentType(input) || who).slice(0, 80);
    dash(['set', who, 'work', label, `subagent started: ${label}`, `speech=เริ่มงาน: ${label}`], project, controlDir);
    exitBridge(input);
  }

  const who = resolveWho(st, input);
  saveState(sid, st);

  if (event === 'postToolUse') {
    const tool = String(input.tool_name || input.tool || '').trim();
    const ti = toolInput(input);
    if (tool === 'Task') {
      const sub = ti.subagent_type || ti.subagentType || ti.agent_type || '';
      if (isLoomAgentType(sub)) {
        const w = mapWho(sub);
        st.who = w;
        st.agent_type = sub;
        const pending = hookAgentId(input) || `task-${sub}`;
        st.subagents = st.subagents || {};
        st.subagents[pending] = w;
        st.activeSubagent = pending;
        saveState(sid, st);
        const label = String(ti.description || ti.prompt || sub).slice(0, 80);
        dash(['delegate', 'orch', w, label, `activity=delegate → ${w}`, `speech=มอบหมาย ${w}`], project, controlDir);
        dash(['set', w, 'work', label, `subagent: ${label}`, `speech=เริ่มงาน: ${label}`], project, controlDir);
      }
      exitBridge(input);
    }
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
    const id = resolveWho(st, input);
    saveState(sid, st);
    let msg = String(
      input.last_assistant_message || input.summary || input.description
      || ex.child_summary || ex.childSummary || ''
    ).trim();
    if (!msg && input.agent_transcript_path && fs.existsSync(input.agent_transcript_path)) {
      try {
        const tail = fs.readFileSync(input.agent_transcript_path, 'utf8').slice(-12000);
        msg = tail.split('\n').slice(-80).join('\n').trim();
      } catch (e) { /* ok */ }
    }
    reportMessage(st, sid, id, msg, project, controlDir);
    clearSubagent(st, input);
    saveState(sid, st);
    exitBridge(input);
  }

  if (event === 'afterAgentResponse') {
    // ponytail: skip root-chat mirroring — subagentStop/stop carry loop summaries
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
  console.assert(!maybeActivateLoom({ loomActive: false }, { prompt: 'fix this bug', cwd: '/tmp' }, 'beforeSubmitPrompt'), 'no activate casual chat');
  console.assert(maybeActivateLoom({ loomActive: false }, { agent_type: 'loom-start' }, 'sessionStart'), 'activate session loom-start');
  console.assert(maybeActivateLoom({ loomActive: false }, { hook_event_name: 'pre_llm_call', extra: { user_message: '/loom-start' } }, 'preLlmCall'), 'activate hermes pre_llm_call');
  console.assert(maybeActivateLoom({ loomActive: false }, { prompt: 'Use loom-start' }, 'beforeSubmitPrompt'), 'activate loop-start');
  console.assert(sessionId({ conversation_id: 'c1', session_id: 's1' }) === 'c1', 'prefer conversation_id');
  console.assert(stateSessionId({ parent_conversation_id: 'p', conversation_id: 'c' }) === 'p', 'cursor parent session');
  const st = { who: 'orch' };
  resolveWho(st, { agent_type: 'loom-fe', hook_event_name: 'PostToolUse' });
  console.assert(st.who === 'fe', 'cc subagent agent_type → fe');
  const stC = { who: 'orch', subagents: {} };
  registerSubagent(stC, { subagent_type: 'loom-fe', subagent_id: 'sub-1' });
  console.assert(stC.who === 'fe' && stC.subagents['sub-1'] === 'fe', 'cursor subagent registry');
  const stA = { who: 'orch', subagents: { 'sub-1': 'fe' }, activeSubagent: 'sub-1' };
  resolveWho(stA, { tool_name: 'Bash' });
  console.assert(stA.who === 'fe', 'active subagent fallback');
  const stH = { who: 'orch' };
  resolveWho(stH, { hook_event_name: 'post_tool_call', extra: { child_role: 'loom-be' } });
  console.assert(stH.who === 'be', 'hermes child_role → be');
  console.assert(isLoomAgentType('loom-orch'), 'loom agent');
  console.assert(!isLoomAgentType('explore'), 'not loom explore');
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
