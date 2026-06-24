#!/usr/bin/env node
/*
 * cc-dash-bridge.js — Claude Code hook → Loom central dashboard.
 * Reads hook JSON on stdin; calls agent-status.js (no chat auto-sync without this).
 *
 * Events: SubagentStart | PostToolUse (Edit|Write|Bash) | SubagentStop | Stop
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const IDS = new Set(['orch', 'pm', 'design', 'be', 'besr', 'fe', 'feanim', 'qa']);
const AGENT_MAP = {
  be: 'be', 'be-sr': 'besr', besr: 'besr',
  fe: 'fe', 'fe-anim': 'feanim', feanim: 'feanim',
  qa: 'qa', pm: 'pm', design: 'design',
  'loop-orch': 'orch', orch: 'orch', 'loop-start': 'orch',
};
const STATE_DIR = path.join(os.homedir(), '.loop-dash');
const SKIP_BASH = /agent-status\.js|dash\.sh|cc-dash-bridge\.js/;

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch (e) { return ''; }
}

function baseDir() {
  try {
    const p = path.join(os.homedir(), '.loop-base');
    const b = fs.readFileSync(p, 'utf8').trim();
    if (b && fs.existsSync(path.join(b, 'agent-dashboard/agent-status.js'))) return b;
  } catch (e) {}
  return path.join(__dirname, '..');
}

function findControl(cwd) {
  let d = cwd;
  for (let i = 0; i < 12 && d && d !== path.dirname(d); i++) {
    const cfg = path.join(d, 'loop.config.json');
    if (fs.existsSync(cfg)) {
      try {
        const j = JSON.parse(fs.readFileSync(cfg, 'utf8'));
        return { dir: d, project: j.project || '' };
      } catch (e) { return { dir: d, project: '' }; }
    }
    d = path.dirname(d);
  }
  return { dir: cwd, project: '' };
}

function mapWho(agentType) {
  if (!agentType) return 'orch';
  const k = String(agentType).toLowerCase();
  if (IDS.has(k)) return k;
  return AGENT_MAP[k] || 'orch';
}

function statePath(sessionId) {
  return path.join(STATE_DIR, `${sessionId || 'default'}.json`);
}

function loadState(sessionId) {
  try { return JSON.parse(fs.readFileSync(statePath(sessionId), 'utf8')); } catch (e) {
    return { who: 'orch', reports: {} };
  }
}

function saveState(sessionId, st) {
  try {
    fs.mkdirSync(STATE_DIR, { recursive: true });
    fs.writeFileSync(statePath(sessionId), JSON.stringify(st, null, 2));
  } catch (e) {}
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
  spawnSync(process.execPath, [script, ...argv], {
    env: { ...process.env, LOOP_PROJECT: project || process.env.LOOP_PROJECT || '' },
    cwd: controlDir,
    stdio: 'ignore',
  });
}

function main() {
  let input;
  try { input = JSON.parse(readStdin() || '{}'); } catch (e) { process.exit(0); }

  const event = input.hook_event_name || '';
  const sessionId = input.session_id || 'default';
  const cwd = input.cwd || process.cwd();
  const { dir: controlDir, project } = findControl(cwd);
  const st = loadState(sessionId);

  if (event === 'SubagentStart') {
    st.who = mapWho(input.agent_type);
    st.agent_type = input.agent_type || '';
    st.cwd = cwd;
    saveState(sessionId, st);
    dash(['set', st.who, 'work', (input.agent_type || 'subagent').slice(0, 80),
      `subagent started: ${input.agent_type || ''}`,
      `speech=เริ่มงาน: ${input.agent_type || st.who}`], project, controlDir);
    process.exit(0);
  }

  const who = st.who || 'orch';

  if (event === 'PostToolUse') {
    const tool = input.tool_name || '';
    if (tool === 'Write' || tool === 'Edit') {
      const ti = input.tool_input || {};
      const fp = relPath(ti.file_path || ti.filePath || '', cwd);
      if (!fp) process.exit(0);
      const action = tool === 'Write' ? 'create' : 'edit';
      let detail = '';
      if (tool === 'Edit' && ti.new_string) {
        detail = String(ti.new_string).split('\n')[0].trim().slice(0, 140);
      } else if (tool === 'Write' && ti.content) {
        detail = String(ti.content).split('\n')[0].trim().slice(0, 140);
      }
      const args = ['file', who, action, fp];
      if (detail) args.push(`detail=${detail}`);
      args.push(`speech=${action === 'create' ? 'สร้าง' : 'แก้'} ${path.basename(fp)}`);
      dash(args, project, controlDir);
    } else if (tool === 'Bash') {
      const cmd = (input.tool_input || {}).command || '';
      if (!cmd || SKIP_BASH.test(cmd)) process.exit(0);
      const short = cmd.length > 160 ? cmd.slice(0, 157) + '…' : cmd;
      dash(['cmd', who, short, `activity=${short.slice(0, 80)}`,
        `speech=${short.slice(0, 100)}`], project, controlDir);
    }
    process.exit(0);
  }

  if (event === 'SubagentStop' || event === 'Stop') {
    const msg = String(input.last_assistant_message || '').trim();
    if (!msg || msg.length < 40) process.exit(0);
    const id = event === 'Stop' ? 'orch' : mapWho(input.agent_type || st.agent_type || st.who);
    const key = `${id}:${msg.slice(0, 200)}`;
    st.reports = st.reports || {};
    if (st.reports[key]) process.exit(0);
    st.reports[key] = Date.now();
    // ponytail: cap dedup map
    const keys = Object.keys(st.reports);
    if (keys.length > 40) {
      for (const k of keys.slice(0, keys.length - 40)) delete st.reports[k];
    }
    saveState(sessionId, st);

    const title = msg.split('\n').find(l => l.trim())?.trim().slice(0, 140) || `${id} update`;
    const speech = title.slice(0, 200);
    const tmp = path.join(STATE_DIR, `report-${Date.now()}.txt`);
    fs.writeFileSync(tmp, msg);
    dash(['report', id, `title=${title}`, `speech=${speech}`, `@${tmp}`], project, controlDir);
    try { fs.unlinkSync(tmp); } catch (e) {}

    const state = /FAIL|fail|error|blocked/i.test(msg) ? 'fix' : 'done';
    dash(['set', id, state, title.slice(0, 80), title.slice(0, 80), `speech=${speech}`], project, controlDir);
    process.exit(0);
  }

  process.exit(0);
}

main();
