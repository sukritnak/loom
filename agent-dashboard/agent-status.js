#!/usr/bin/env node
/*
 * agent-status.js — live status writer for the central AI Agent Office dashboard.
 * Writes status.json next to this file (the ONE board in the blueprint). The dashboard polls it.
 * Prefer calling it through `zsh tools/dash.sh <cmd...>` from a project: that resolves the Base
 * dashboard and sets LOOP_PROJECT so every state/log line is tagged with the project name.
 *
 * Usage:
 *   node agent-status.js reset ["task title"]      reset all agents to idle, clear log
 *   node agent-status.js task  "task title"        set the current task / sprint title
 *   node agent-status.js loop  <n>                 set the loop round number
 *   node agent-status.js set <id> <state> ["task text"] ["log message"]
 *   node agent-status.js log <who> "message"       append a feed line (no state change)
 *
 *   <id>    = orch | pm | design | be | besr | fe | feanim | qa
 *   <state> = idle | work | fix | done
 *
 * Examples:
 *   node agent-status.js reset "add email password reset"
 *   node agent-status.js set orch work "วางแผน loop" "รับงานเข้ามา"
 *   node agent-status.js set pm done "AC พร้อม 4 ข้อ" "ส่ง acceptance criteria"
 *   node agent-status.js loop 2
 */
const fs = require('fs');
const path = require('path');

const FILE = path.join(__dirname, 'status.json');
const IDS = ['orch', 'pm', 'design', 'be', 'besr', 'fe', 'feanim', 'qa'];
const STATES = ['idle', 'work', 'fix', 'done'];
// Which project this call belongs to (set by tools/dash.sh from the project's loop.config.json).
// This is the ONE central board: every project/session writes here, tagged so work is told apart.
const PROJECT = process.env.LOOP_PROJECT || '';

function emptyState(task) {
  const agents = {};
  IDS.forEach(id => { agents[id] = { state: 'idle', task: '' }; });
  return { task: task || '', project: PROJECT, loop: 1, updatedAt: new Date().toISOString(), agents, log: [] };
}
function tagProject(s) { if (PROJECT) s.project = PROJECT; }
function load() {
  try { return JSON.parse(fs.readFileSync(FILE, 'utf8')); }
  catch (e) { return emptyState(''); }
}
function save(s) {
  s.updatedAt = new Date().toISOString();
  fs.writeFileSync(FILE, JSON.stringify(s, null, 2));
}
function hhmm() {
  const d = new Date();
  return ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2);
}
function pushLog(s, who, msg) {
  s.log.push({ t: hhmm(), who, msg, project: s.project || PROJECT || '' });
  if (s.log.length > 300) s.log = s.log.slice(-300); // ponytail: rolling cross-project history, cap 300
}

const [, , cmd, ...args] = process.argv;
const s = load();

switch ((cmd || '').toLowerCase()) {
  case 'reset': {
    // Keep the rolling log across tasks/projects/sessions (the central board sees ALL work);
    // only reset agent states + task + loop, then drop a labelled separator.
    const ns = emptyState(args[0] || '');
    ns.log = Array.isArray(s.log) ? s.log : [];
    pushLog(ns, 'orch', '── new task: ' + (PROJECT ? '[' + PROJECT + '] ' : '') + (args[0] || '(untitled)') + ' ──');
    save(ns);
    console.log('status reset' + (PROJECT ? ' · project: ' + PROJECT : '') + (args[0] ? ' · task: ' + args[0] : ''));
    break;
  }
  case 'task':
    if (!args[0]) { console.error('usage: task "title"'); process.exit(1); }
    s.task = args[0]; tagProject(s); save(s); console.log('task set: ' + args[0]);
    break;
  case 'loop': {
    const n = parseInt(args[0], 10);
    if (!n) { console.error('usage: loop <n>'); process.exit(1); }
    s.loop = n; tagProject(s); save(s); console.log('loop = ' + n);
    break;
  }
  case 'set': {
    const [id, state, taskText, logMsg] = args;
    if (!IDS.includes(id)) { console.error('bad id. use: ' + IDS.join(' | ')); process.exit(1); }
    if (!STATES.includes(state)) { console.error('bad state. use: ' + STATES.join(' | ')); process.exit(1); }
    tagProject(s);
    s.agents[id].state = state;
    if (taskText != null) s.agents[id].task = taskText;
    if (logMsg) pushLog(s, id, logMsg);
    save(s);
    console.log(`${id} -> ${state}${taskText ? ' (' + taskText + ')' : ''}`);
    break;
  }
  case 'log': {
    const [who, msg] = args;
    if (!who || !msg) { console.error('usage: log <who> "message"'); process.exit(1); }
    tagProject(s); pushLog(s, who, msg); save(s); console.log('logged: ' + who + ' ' + msg);
    break;
  }
  default:
    console.log('commands: reset | task | loop | set | log  (see header of this file)');
}
