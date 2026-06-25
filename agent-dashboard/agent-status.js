#!/usr/bin/env node
/*
 * agent-status.js — live status writer for the central AI Agent Software Team dashboard.
 * Writes status.json next to this file (the ONE board in the blueprint). The dashboard polls it.
 * Prefer calling it through `zsh tools/dash.sh <cmd...>` from a project: that resolves the Base
 * dashboard and sets LOOP_PROJECT so every state/log line is tagged with the project name.
 *
 * Usage:
 *   node agent-status.js reset ["task title"]      reset agents to idle; keeps rolling log
 *   node agent-status.js clearlog                  archive log to log-archive/status-YYYY-MM-DD.json (date from last entry), clear feed
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
 *   node agent-status.js file-append <who> "<path>" [detail="more lines"] [lines="+N -M"] [speech=...]
 *       append detail to the latest file log for the same who+path (rapid hook coalesce)
 *   node agent-status.js report <who> title="..." [speech="bubble TL;DR"] [--stdin | @file | body...]
 *       full agent return — same depth as chat (root cause, branch, AC table, gates). kind=report.
 *   node agent-status.js wait <who> "waiting for …" [speech=...]  — orch waiting on background agents
 *   <state> = idle | work | fix | done
 */
const fs = require('fs');
const path = require('path');
const { skillLabel, cmdLabel } = require('./capability-labels');
const { cleanProject, resolveProject, resolveControlDir, resolveDisplayPath } = require(path.join(__dirname, '../tools/resolve-project.js'));

const FILE = path.join(__dirname, 'status.json');
const ARCHIVE_DIR = path.join(__dirname, 'log-archive');
const IDS = ['orch', 'pm', 'design', 'be', 'besr', 'fe', 'feanim', 'qa'];
const STATES = ['idle', 'work', 'fix', 'done'];
const META_KEYS = ['kind', 'to', 'skill', 'cmd', 'activity', 'title', 'speech', 'file', 'action', 'detail', 'removed', 'added', 'lines', 'lineStart', 'lineEnd', 'removedLineStart', 'addedLineStart'];
const FILE_ACTIONS = ['create', 'edit', 'delete', 'rename'];
const PROJECT = cleanProject(process.env.LOOP_PROJECT || '');
const LOG_CAP = 400; // ponytail: rolling in-memory feed; older lines → log-archive/
const MSG_CAP = 12000; // max chars per say/report line

function todayKey() { return new Date().toISOString().slice(0, 10); }

const DAY_KEY_RE = /^\d{4}-\d{2}-\d{2}$/;

/** Archive filename day — last log entry's `at` date, else logDay, else today. */
function dayKeyFromLog(entries, fallback) {
  const log = Array.isArray(entries) ? entries : [];
  for (let i = log.length - 1; i >= 0; i--) {
    const at = log[i]?.at;
    if (typeof at === 'string' && at.length >= 10) {
      const d = at.slice(0, 10);
      if (DAY_KEY_RE.test(d)) return d;
    }
  }
  const fb = String(fallback || '');
  if (DAY_KEY_RE.test(fb)) return fb;
  return todayKey();
}

function archiveLogEntries(entries, dayKey) {
  if (!entries.length) return 0;
  fs.mkdirSync(ARCHIVE_DIR, { recursive: true });
  const file = path.join(ARCHIVE_DIR, `status-${dayKey}.json`);
  let existing = [];
  try {
    const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
    existing = Array.isArray(raw) ? raw : [];
  } catch (e) { /* new archive file */ }
  fs.writeFileSync(file, JSON.stringify(existing.concat(entries), null, 2));
  return entries.length;
}

function maybeRotateDailyLog(s) {
  const today = todayKey();
  if (!s.logDay) { s.logDay = today; return; }
  if (s.logDay === today) return;
  const log = Array.isArray(s.log) ? s.log : [];
  if (log.length) archiveLogEntries(log, s.logDay);
  s.log = [];
  s.logDay = today;
}

function clearLog(s) {
  const log = Array.isArray(s.log) ? s.log : [];
  const dayKey = dayKeyFromLog(log, s.logDay);
  const n = archiveLogEntries(log, dayKey);
  s.log = [];
  s.logDay = todayKey();
  return { n, dayKey };
}

function emptyState(task) {
  const agents = {};
  IDS.forEach(id => { agents[id] = { state: 'idle', task: '' }; });
  return { task: task || '', project: PROJECT, loop: 1, logDay: todayKey(), updatedAt: new Date().toISOString(), agents, log: [] };
}
function tagProject(s) { if (PROJECT) s.project = PROJECT; }
function load() {
  try { return JSON.parse(fs.readFileSync(FILE, 'utf8')); }
  catch (e) { return emptyState(''); }
}
function save(s) {
  maybeRotateDailyLog(s);
  if (!s.logDay) s.logDay = todayKey();
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

/** @path.json sidecar from dash-bridge — { removed, added } with full multiline diff. */
function loadEditJson(rest) {
  const metaArgs = [];
  let payload = {};
  for (const a of rest) {
    const s = String(a);
    if (s.startsWith('@')) {
      try {
        const p = s.slice(1);
        if (fs.existsSync(p)) payload = { ...payload, ...JSON.parse(fs.readFileSync(p, 'utf8')) };
      } catch (e) { /* ok */ }
    } else metaArgs.push(a);
  }
  return { payload, metaArgs };
}
function pushLog(s, who, msg, meta = {}) {
  const body = String(msg || '');
  const entry = {
    t: hhmm(), at: new Date().toISOString(), who,
    msg: body.length > MSG_CAP ? body.slice(0, MSG_CAP) + '\n…(truncated)' : body,
    ...pickMeta(meta),
  };
  const proj = cleanProject(s.project || PROJECT);
  if (proj) entry.project = proj;
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
  case 'clearlog': {
    const { n, dayKey } = clearLog(s);
    save(s);
    const archiveId = 'status-' + dayKey + '.json';
    console.log('log cleared (' + n + ' entries archived to log-archive/' + archiveId + ')');
    if (n > 0) console.log('ARCHIVE:' + JSON.stringify({ id: archiveId, date: dayKey, added: n }));
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
    const { payload, metaArgs } = loadEditJson(rest);
    const parsed = pickMeta(parseMeta(metaArgs));
    const removed = payload.removed || parsed.removed || '';
    const added = payload.added || parsed.added || parsed.detail || '';
    const lines = parsed.lines || '';
    const controlDir = process.env.LOOP_CONTROL_DIR || resolveControlDir(process.cwd());
    const displayPath = resolveDisplayPath(filePath, controlDir);
    const base = path.basename(String(displayPath).split('→')[0].trim());
    const verb = { create: 'สร้าง', edit: 'แก้', delete: 'ลบ', rename: 'ย้าย' }[action] || action;
    const task = (parsed.activity || `${verb} ${base}`).slice(0, 100);
    const msgParts = [`${action} · ${displayPath}`];
    if (s.agents[who].state !== 'fix') s.agents[who].state = 'work';
    s.agents[who].task = task;
    s.agents[who].file = String(displayPath).slice(0, 160);
    pushLog(s, who, msgParts.join('\n'), ensureSpeech({
      kind: 'file', action, file: displayPath, detail: added, removed, added, lines, activity: task, ...parsed,
    }, msgParts.join('\n')));
    save(s);
    console.log('file: ' + who + ' · ' + action + ' · ' + displayPath);
    break;
  }
  case 'file-append': {
    const [who, filePath, ...rest] = args;
    if (!IDS.includes(who)) { console.error('bad id. use: ' + IDS.join(' | ')); process.exit(1); }
    if (!filePath) { console.error('usage: file-append <who> "<path>" [detail=...] [lines=...] [speech=...]'); process.exit(1); }
    tagProject(s);
    const { payload, metaArgs } = loadEditJson(rest);
    const parsed = pickMeta(parseMeta(metaArgs));
    const addDetail = payload.added || parsed.added || parsed.detail || '';
    const addRemoved = payload.removed || parsed.removed || '';
    const addLines = parsed.lines || '';
    const controlDir = process.env.LOOP_CONTROL_DIR || resolveControlDir(process.cwd());
    const displayPath = resolveDisplayPath(filePath, controlDir);
    const base = path.basename(String(displayPath).split('→')[0].trim());
    const log = Array.isArray(s.log) ? s.log : [];
    let entry = null;
    for (let i = log.length - 1; i >= 0; i--) {
      const e = log[i];
      if (e.who === who && e.kind === 'file' && e.file === displayPath) { entry = e; break; }
    }
    if (!entry) {
      const verb = 'แก้';
      const task = (parsed.activity || `${verb} ${base}`).slice(0, 100);
      if (s.agents[who].state !== 'fix') s.agents[who].state = 'work';
      s.agents[who].task = task;
      s.agents[who].file = String(displayPath).slice(0, 160);
      pushLog(s, who, `edit · ${displayPath}`, ensureSpeech({
        kind: 'file', action: 'edit', file: displayPath,
        detail: addDetail, removed: addRemoved, added: addDetail, lines: addLines, activity: task, ...parsed,
      }, `edit · ${displayPath}`));
      save(s);
      console.log('file-append (new): ' + who + ' · ' + displayPath);
      break;
    }
    if (addRemoved) entry.removed = entry.removed ? `${entry.removed}\n${addRemoved}` : addRemoved;
    if (addDetail) {
      entry.added = entry.added ? `${entry.added}\n${addDetail}` : addDetail;
      entry.detail = entry.added;
    }
    if (addLines) entry.lines = addLines;
    if (parsed.lineStart && !entry.lineStart) entry.lineStart = parsed.lineStart;
    if (parsed.removedLineStart && !entry.removedLineStart) entry.removedLineStart = parsed.removedLineStart;
    if (parsed.addedLineStart && !entry.addedLineStart) entry.addedLineStart = parsed.addedLineStart;
    if (parsed.lineEnd) {
      const cur = parseInt(entry.lineEnd, 10) || 0;
      const neu = parseInt(parsed.lineEnd, 10) || 0;
      if (neu > cur) entry.lineEnd = parsed.lineEnd;
    } else if (parsed.lineStart && !entry.lineEnd) entry.lineEnd = parsed.lineStart;
    entry.msg = `${entry.action || 'edit'} · ${displayPath}`;
    if (parsed.speech) entry.speech = parsed.speech;
    if (s.agents[who].state !== 'fix') s.agents[who].state = 'work';
    s.agents[who].file = String(displayPath).slice(0, 160);
    save(s);
    console.log('file-append: ' + who + ' · ' + displayPath);
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
    console.log('commands: reset | clearlog | task | loop | set | log | event | delegate | skill | cmd | progress | file | report | wait | say');
}
