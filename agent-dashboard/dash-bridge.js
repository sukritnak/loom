#!/usr/bin/env node
/*
 * dash-bridge.js — universal hook bridge → Loom central dashboard.
 * Claude Code (~/.claude/settings.json) + Cursor (~/.cursor/hooks.json).
 *
 * Usage: node dash-bridge.js [eventHint]
 *   eventHint optional when hook_event_name is missing (Cursor afterAgentResponse).
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { cleanProject, resolveProject, resolveControlDir } = require(path.join(__dirname, '../tools/resolve-project.js'));
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
  /(^|\/)tools\/(dash\.sh|resolve-project\.js|install-(dash|cursor|cc)-hooks\.sh)$/,
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

function normalizeEvent(input) {
  const raw = input.hook_event_name || EVENT_HINT || '';
  const e = String(raw).toLowerCase();
  const map = {
    subagentstart: 'subagentStart',
    posttooluse: 'postToolUse',
    subagentstop: 'subagentStop',
    afteragentresponse: 'afterAgentResponse',
    afterfileedit: 'afterFileEdit',
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

function handleFile(who, action, fp, detail, project, controlDir, st, sid) {
  if (!fp || shouldSkipFile(fp)) return;
  const key = `${who}:${action}:${normPath(fp)}`;
  if (recentKey(st, 'recentFiles', key)) return;
  saveState(sid, st);
  const base = path.basename(String(fp).split('→')[0].trim());
  const verb = action === 'create' ? 'สร้าง' : action === 'delete' ? 'ลบ' : 'แก้';
  const d = cleanDetail(detail);
  const args = ['file', who, action, fp];
  if (d) args.push(`detail=${d}`);
  args.push(`speech=${verb} ${base}`);
  dash(args, project, controlDir);
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
    const who = mapWho(input.agent_type || input.subagent_type);
    st.who = who;
    st.agent_type = input.agent_type || input.subagent_type || '';
    st.cwd = cwd;
    saveState(sid, st);
    const label = (input.task || input.agent_type || input.subagent_type || who).slice(0, 80);
    dash(['set', who, 'work', label, `subagent started: ${label}`, `speech=เริ่มงาน: ${label}`], project, controlDir);
    process.exit(0);
  }

  const who = st.who || mapWho(input.agent_type || input.subagent_type) || 'orch';

  if (event === 'postToolUse') {
    const tool = input.tool_name || '';
    const ti = input.tool_input || {};
    if (tool === 'Write' || tool === 'Edit') {
      const fp = relPath(ti.file_path || ti.filePath || '', cwd);
      handleFile(who, tool === 'Write' ? 'create' : 'edit', fp,
        tool === 'Edit' && ti.new_string ? String(ti.new_string).split('\n')[0].trim().slice(0, 140)
          : tool === 'Write' && ti.content ? String(ti.content).split('\n')[0].trim().slice(0, 140) : '',
        project, controlDir, st, sid);
    } else if (tool === 'StrReplace') {
      const fp = relPath(ti.path || ti.file_path || ti.filePath || '', cwd);
      const detail = ti.new_string ? String(ti.new_string).split('\n')[0].trim().slice(0, 140) : '';
      handleFile(who, 'edit', fp, detail, project, controlDir, st, sid);
    } else if (tool === 'Delete') {
      const fp = relPath(ti.path || ti.file_path || '', cwd);
      handleFile(who, 'delete', fp, '', project, controlDir, st, sid);
    } else if (tool === 'Shell' || tool === 'Bash') {
      handleShell(who, ti.command || '', project, controlDir, st, sid);
    }
    process.exit(0);
  }

  if (event === 'afterFileEdit') {
    const fp = relPath(input.file_path || '', cwd);
    const edit = Array.isArray(input.edits) && input.edits[0];
    const detail = edit && edit.new_string ? String(edit.new_string).split('\n')[0].trim().slice(0, 140) : '';
    handleFile(who, 'edit', fp, detail, project, controlDir, st, sid);
    process.exit(0);
  }

  if (event === 'afterShellExecution') {
    handleShell(who, input.command || '', project, controlDir, st, sid);
    process.exit(0);
  }

  if (event === 'subagentStop') {
    const id = mapWho(input.agent_type || input.subagent_type || st.agent_type || st.who);
    let msg = String(input.summary || input.last_assistant_message || '').trim();
    if (!msg && input.agent_transcript_path && fs.existsSync(input.agent_transcript_path)) {
      try {
        const tail = fs.readFileSync(input.agent_transcript_path, 'utf8').slice(-12000);
        msg = tail.split('\n').slice(-80).join('\n').trim();
      } catch (e) { /* ok */ }
    }
    reportMessage(st, sid, id, msg, project, controlDir);
    process.exit(0);
  }

  if (event === 'afterAgentResponse') {
    reportMessage(st, sid, 'orch', input.text || '', project, controlDir);
    cursorOk();
    process.exit(0);
  }

  if (event === 'stop') {
    const msg = String(input.last_assistant_message || '').trim();
    const recent = st.lastReportAt && (Date.now() - st.lastReportAt < 8000);
    if (!recent && msg) reportMessage(st, sid, 'orch', msg, project, controlDir);
    process.exit(0);
  }

  process.exit(0);
}

if (process.argv.includes('--self-check')) {
  console.assert(shouldSkipShell('node -e "require(\'status.json\')"'), 'skip node -e');
  console.assert(shouldSkipShell('cd /tmp && node resolve-project.js'), 'skip resolve');
  console.assert(shouldSkipFile('agent-dashboard/dash-bridge.js'), 'skip dash-bridge file');
  console.assert(cleanDetail('#!/usr/bin/env node') === '', 'strip shebang');
  console.assert(!shouldSkipShell('npm test'), 'keep npm test');
  console.assert(cmdLabel('npm test'), 'label npm test');
  console.log('dash-bridge self-check ok');
  process.exit(0);
}

main();
