#!/usr/bin/env node
/*
 * agent-status.js — live status writer for the central AI Agent Software Team dashboard.
 * Writes status.json next to this file (the ONE board in the blueprint). The dashboard polls it.
 * Prefer calling it through `zsh tools/dash.sh <cmd...>` from a project: that resolves the Base
 * dashboard and sets LOOP_PROJECT so every state/log line is tagged with the project name.
 *
 * Usage:
 *   node agent-status.js reset ["task title"]      reset agents to idle; keeps rolling log
 *   node agent-status.js task  "task title"        set the current task / sprint title
 *   node agent-status.js loop  <n>                 set the loop round number
 *   node agent-status.js set <id> <state> ["task text"] ["log message"]
 *   node agent-status.js log <who> "message"       simple feed line (no state change)
 *   node agent-status.js event <who> "message" [key=value ...]
 *       keys: kind=delegate|skill|cmd|chat|system  to=<id>  skill=<name>  cmd=<shell>
 *       activity=<feed detail>  speech=<bubble — conversational Thai/English, NOT raw commands>
 *   node agent-status.js delegate <from> <to> "message" [activity=<text>] [skill=<name>] [cmd=<shell>]
 *   node agent-status.js skill <who> "<skillName>" [activity=<text>] [cmd=<shell>]
 *   node agent-status.js cmd <who> "<command>" [activity=<text>] [skill=<name>]
 *   node agent-status.js progress <who> "message" [speech=...] [activity=...]
 *       in-flight update: keeps agent on work, refreshes task + bubble (use during long plans/builds)
 *   node agent-status.js say <who> [title="..."] [kind=say|report|test] [--stdin | @file | body...]
 *       long agent speech / audit / test report (multiline — use heredoc with --stdin)
 *   node agent-status.js file <who> <action> "<path>" [detail="what changed"] [lines="+N -M"] [speech=...]
 *       action = create | edit | delete | rename  (rename path: "old/path → new/path")
 *   node agent-status.js report <who> title="..." [speech="bubble TL;DR"] [--stdin | @file | body...]
 *       full agent return — same depth as chat (root cause, branch, AC table, gates). kind=report.
 *   node agent-status.js wait <who> "waiting for …" [speech=...]  — orch waiting on background agents
 *   <state> = idle | work | fix | done
 */
const fs = require('fs');
const path = require('path');
const { skillLabel, cmdLabel } = require('./capability-labels');

const FILE = path.join(__dirname, 'status.json');
const IDS = ['orch', 'pm', 'design', 'be', 'besr', 'fe', 'feanim', 'qa'];
const STATES = ['idle', 'work', 'fix', 'done'];
const META_KEYS = ['kind', 'to', 'skill', 'cmd', 'activity', 'title', 'speech', 'file', 'action', 'detail', 'lines'];
const FILE_ACTIONS = ['create', 'edit', 'delete', 'rename'];
const PROJECT = process.env.LOOP_PROJECT || '';
const LOG_CAP = 800; // ponytail: rolling cross-project history
const MSG_CAP = 12000; // max chars per say/report line

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
function parseMeta(args) {
  const meta = {};
  for (const a of args) {
    const i = String(a).indexOf('=');
    if (i > 0) meta[a.slice(0, i)] = a.slice(i + 1);
  }
  return meta;
}
function pickMeta(meta) {
  const o = {};
  for (const k of META_KEYS) if (meta[k]) o[k] = meta[k];
  return o;
}
function pushLog(s, who, msg, meta = {}) {
  const body = String(msg || '');
  const entry = {
    t: hhmm(), at: new Date().toISOString(), who,
    msg: body.length > MSG_CAP ? body.slice(0, MSG_CAP) + '\n…(truncated)' : body,
    project: s.project || PROJECT || '',
    ...pickMeta(meta),
  };
  s.log.push(entry);
  if (s.log.length > LOG_CAP) s.log = s.log.slice(-LOG_CAP);
}
function readStdin() {
  if (process.stdin.isTTY) return '';
  return fs.readFileSync(0, 'utf8').trim();
}
function parseLongBody(args) {
  let title = '';
  let kind = '';
  let body = '';
  let useStdin = false;
  const metaArgs = [];
  for (const a of args) {
    if (a === '--stdin') useStdin = true;
    else if (a.startsWith('title=')) title = a.slice(6);
    else if (a.startsWith('kind=')) kind = a.slice(5);
    else if (a.startsWith('@')) body = fs.readFileSync(a.slice(1), 'utf8').trim();
    else if (a.includes('=')) metaArgs.push(a);
    else body = body ? body + '\n' + a : a;
  }
  if (useStdin) body = readStdin() || body;
  return { title, kind, body, metaArgs };
}
function doLongMessage(s, who, defaultKind, args, usage, logPrefix) {
  if (!IDS.includes(who)) { console.error('bad id. use: ' + IDS.join(' | ')); process.exit(1); }
  const { title: t0, kind: k0, body, metaArgs } = parseLongBody(args);
  if (!body) { console.error(usage); process.exit(1); }
  const kind = k0 || defaultKind;
  const title = t0 || body.split('\n').find(l => l.trim())?.trim().slice(0, 140) || 'update';
  tagProject(s);
  s.agents[who].task = title.slice(0, 100);
  pushLog(s, who, body, ensureSpeech({ kind, title, activity: title, ...pickMeta(parseMeta(metaArgs)) }, title));
  save(s);
  console.log(logPrefix + ': ' + who + ' · ' + title.slice(0, 60));
}
function ensureSpeech(meta, msg) {
  const m = { ...meta };
  if (m.speech) return m;
  // activity= / progress msg = explicit from dash.sh caller
  if (m.activity) m.speech = String(m.activity).slice(0, 320);
  else if (m.kind === 'progress' && msg) m.speech = String(msg).slice(0, 320);
  else if (m.title) m.speech = m.title;
  else if (m.kind === 'skill' && m.skill) {
    const label = skillLabel(m.skill);
    if (label) m.speech = label;
  } else if (m.kind === 'cmd' && m.cmd) {
    const label = cmdLabel(m.cmd);
    if (label) m.speech = label;
  } else if (m.kind === 'file' && m.file) {
    const verb = { create: 'สร้าง', edit: 'แก้', delete: 'ลบ', rename: 'ย้าย' }[m.action] || m.action || 'แก้';
    const base = path.basename(String(m.file).split('→')[0].trim());
    m.speech = (verb + ' ' + base + (m.detail ? ' — ' + String(m.detail).slice(0, 120) : '')).slice(0, 320);
  }
  return m;
}

const [, , cmd, ...args] = process.argv;
const s = load();

switch ((cmd || '').toLowerCase()) {
  case 'reset': {
    const ns = emptyState(args[0] || '');
    ns.log = Array.isArray(s.log) ? s.log : [];
    pushLog(ns, 'orch', '── new task: ' + (PROJECT ? '[' + PROJECT + '] ' : '') + (args[0] || '(untitled)') + ' ──', { kind: 'system' });
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
    s.loop = n; tagProject(s);
    pushLog(s, 'orch', 'loop round ' + n, { kind: 'system' });
    save(s); console.log('loop = ' + n);
    break;
  }
  case 'set': {
    const [id, state, taskText, logMsg, ...rest] = args;
    if (!IDS.includes(id)) { console.error('bad id. use: ' + IDS.join(' | ')); process.exit(1); }
    if (!STATES.includes(state)) { console.error('bad state. use: ' + STATES.join(' | ')); process.exit(1); }
    tagProject(s);
    s.agents[id].state = state;
    if (taskText != null) s.agents[id].task = taskText;
    if (logMsg) pushLog(s, id, logMsg, ensureSpeech({ kind: 'state', activity: taskText || '', ...pickMeta(parseMeta(rest)) }, logMsg));
    save(s);
    console.log(`${id} -> ${state}${taskText ? ' (' + taskText + ')' : ''}`);
    break;
  }
  case 'log': {
    const [who, msg, ...rest] = args;
    if (!who || !msg) { console.error('usage: log <who> "message" [key=value ...]'); process.exit(1); }
    tagProject(s); pushLog(s, who, msg, ensureSpeech({ kind: 'chat', ...pickMeta(parseMeta(rest)) }, msg)); save(s);
    console.log('logged: ' + who + ' ' + msg);
    break;
  }
  case 'event': {
    const [who, msg, ...rest] = args;
    if (!who || !msg) { console.error('usage: event <who> "message" [kind=...] [to=...] [skill=...] [cmd=...] [activity=...]'); process.exit(1); }
    tagProject(s); pushLog(s, who, msg, ensureSpeech(pickMeta(parseMeta(rest)), msg)); save(s);
    console.log('event: ' + who + ' ' + msg);
    break;
  }
  case 'delegate': {
    const [from, to, msg, ...rest] = args;
    if (!from || !to || !msg) { console.error('usage: delegate <from> <to> "message" [activity=...] [skill=...] [cmd=...]'); process.exit(1); }
    if (!IDS.includes(from) || !IDS.includes(to)) { console.error('bad id in from/to'); process.exit(1); }
    tagProject(s);
    pushLog(s, from, msg, ensureSpeech({ kind: 'delegate', to, ...pickMeta(parseMeta(rest)) }, msg));
    save(s);
    console.log('delegate: ' + from + ' → ' + to);
    break;
  }
  case 'skill': {
    const [who, skillName, ...rest] = args;
    if (!who || !skillName) { console.error('usage: skill <who> "<skillName>" [activity=...] [cmd=...]'); process.exit(1); }
    tagProject(s);
    const parsed = pickMeta(parseMeta(rest));
    const meta = ensureSpeech({ kind: 'skill', skill: skillName, ...parsed }, parsed.activity || '');
    pushLog(s, who, 'skill · ' + skillName, meta);
    save(s);
    console.log('skill: ' + who + ' · ' + skillName);
    break;
  }
  case 'cmd': {
    const [who, command, ...rest] = args;
    if (!who || !command) { console.error('usage: cmd <who> "<command>" [activity=...] [skill=...]'); process.exit(1); }
    tagProject(s);
    const parsed = pickMeta(parseMeta(rest));
    const meta = ensureSpeech({ kind: 'cmd', cmd: command, ...parsed }, parsed.activity || '');
    pushLog(s, who, command, meta);
    save(s);
    console.log('cmd: ' + who + ' · ' + command);
    break;
  }
  case 'progress': {
    const [who, msg, ...rest] = args;
    if (!IDS.includes(who)) { console.error('bad id. use: ' + IDS.join(' | ')); process.exit(1); }
    if (!msg) { console.error('usage: progress <who> "message" [speech=...] [activity=...]'); process.exit(1); }
    tagProject(s);
    const parsed = pickMeta(parseMeta(rest));
    const task = String(parsed.activity || msg).slice(0, 100);
    if (s.agents[who].state !== 'fix') s.agents[who].state = 'work';
    s.agents[who].task = task;
    pushLog(s, who, msg, ensureSpeech({ kind: 'progress', activity: task, ...parsed }, msg));
    save(s);
    console.log('progress: ' + who + ' · ' + msg.slice(0, 60));
    break;
  }
  case 'file': {
    const [who, action, filePath, ...rest] = args;
    if (!IDS.includes(who)) { console.error('bad id. use: ' + IDS.join(' | ')); process.exit(1); }
    if (!FILE_ACTIONS.includes(action)) { console.error('bad action. use: ' + FILE_ACTIONS.join(' | ')); process.exit(1); }
    if (!filePath) { console.error('usage: file <who> <action> "<path>" [detail=...] [lines=...] [speech=...]'); process.exit(1); }
    tagProject(s);
    const parsed = pickMeta(parseMeta(rest));
    const detail = parsed.detail || '';
    const lines = parsed.lines || '';
    const base = path.basename(String(filePath).split('→')[0].trim());
    const verb = { create: 'สร้าง', edit: 'แก้', delete: 'ลบ', rename: 'ย้าย' }[action] || action;
    const task = (verb + ' ' + base).slice(0, 100);
    const msgParts = [action + ' · ' + filePath];
    if (detail) msgParts.push(detail);
    if (lines) msgParts.push(lines);
    if (s.agents[who].state !== 'fix') s.agents[who].state = 'work';
    s.agents[who].task = task;
    s.agents[who].file = String(filePath).slice(0, 160);
    pushLog(s, who, msgParts.join('\n'), ensureSpeech({
      kind: 'file', action, file: filePath, detail, lines, activity: task, ...parsed,
    }, msgParts.join('\n')));
    save(s);
    console.log('file: ' + who + ' · ' + action + ' · ' + filePath);
    break;
  }
  case 'wait': {
    const [who, msg, ...rest] = args;
    if (!IDS.includes(who)) { console.error('bad id. use: ' + IDS.join(' | ')); process.exit(1); }
    if (!msg) { console.error('usage: wait <who> "waiting for …" [speech=...]'); process.exit(1); }
    tagProject(s);
    const parsed = pickMeta(parseMeta(rest));
    const task = String(parsed.activity || msg).slice(0, 100);
    s.agents[who].state = 'work';
    s.agents[who].task = task;
    pushLog(s, who, msg, ensureSpeech({ kind: 'wait', activity: task, ...parsed }, msg));
    save(s);
    console.log('wait: ' + who + ' · ' + msg.slice(0, 60));
    break;
  }
  case 'report': {
    const who = args[0];
    doLongMessage(s, who, 'report', args.slice(1),
      'usage: report <who> title="..." [speech=...] [--stdin | @file | text]',
      'report');
    break;
  }
  case 'say': {
    const who = args[0];
    doLongMessage(s, who, 'say', args.slice(1),
      'usage: say <who> title="..." [--stdin | @file | text]',
      'say');
    break;
  }
  default:
    console.log('commands: reset | task | loop | set | log | event | delegate | skill | cmd | progress | file | report | wait | say');
}
