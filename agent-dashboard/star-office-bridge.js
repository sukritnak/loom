#!/usr/bin/env node
/*
 * star-office-bridge.js — mirror the loop's status.json into the vendored Star-Office-UI.
 */
const fs = require('fs');
const path = require('path');
const { skillLabel, cmdLabel } = require('./capability-labels');

const DIR = __dirname;
const SRC = path.join(DIR, 'status.json');
const STAR = path.join(DIR, 'star-office');
const AGENTS_FILE = path.join(STAR, 'agents-state.json');
const STATE_FILE = path.join(STAR, 'state.json');
const ACTIVITY_FILE = path.join(STAR, 'activity.json');

const TEAM = [
  { id: 'orch',   name: 'Orchestrator',  main: true },
  { id: 'pm',     name: 'PM',             avatar: 'guest_role_1' },
  { id: 'design', name: 'Designer',       avatar: 'guest_role_2' },
  { id: 'be',     name: 'Backend',        avatar: 'guest_role_3' },
  { id: 'besr',   name: 'Backend Sr.',    avatar: 'guest_role_4' },
  { id: 'fe',     name: 'Frontend',       avatar: 'guest_role_5' },
  { id: 'feanim', name: 'Frontend Anim',  avatar: 'guest_role_6' },
  { id: 'qa',     name: 'QA',             avatar: 'guest_role_1' },
];
const MAP = { work: 'writing', fix: 'error', done: 'idle', idle: 'idle' };
const AREA = { writing: 'writing', error: 'error', idle: 'breakroom' };

function officePresence(loopState) {
  const st = MAP[loopState] || 'idle';
  return { state: st, area: AREA[st] || 'breakroom', involved: st !== 'idle' };
}

function read() {
  try { return JSON.parse(fs.readFileSync(SRC, 'utf8')); } catch (e) { return null; }
}

function latestLogFor(log, id) {
  if (!Array.isArray(log)) return null;
  for (let i = log.length - 1; i >= 0; i--) {
    if (log[i].who === id) return log[i];
  }
  return null;
}

/** Bubble = explicit speech only, or fixed capability label from capability-labels.js */
function bubbleText(latest) {
  if (!latest) return '';
  if (latest.speech) return String(latest.speech).slice(0, 420);
  if (latest.title && ['say', 'report', 'test'].includes(latest.kind)) {
    return String(latest.title).slice(0, 420);
  }
  if (latest.kind === 'skill' && latest.skill) {
    const label = skillLabel(latest.skill);
    if (label) return label;
  }
  if (latest.kind === 'cmd' && latest.cmd) {
    const label = cmdLabel(latest.cmd);
    if (label) return label;
  }
  if (latest.kind === 'progress' && latest.msg) return String(latest.msg).slice(0, 320);
  if (latest.kind === 'file' && latest.file) {
    const verb = { create: 'สร้าง', edit: 'แก้', delete: 'ลบ', rename: 'ย้าย' }[latest.action] || latest.action || 'แก้';
    const base = path.basename(String(latest.file).split('→')[0].trim());
    const tail = latest.detail ? ' — ' + String(latest.detail).slice(0, 100) : '';
    return (verb + ' ' + base + tail).slice(0, 420);
  }
  return '';
}

function detailLine(a, latest, involved) {
  const speech = bubbleText(latest);
  if (speech) return speech.split('\n')[0].slice(0, 140);
  return involved ? (a.task || '') : '';
}

function statusBarLine(latest) {
  if (!latest) return '';
  return bubbleText(latest).split('\n')[0].slice(0, 200);
}

function build(s) {
  const now = new Date().toISOString();
  const far = new Date(Date.now() + 24 * 3600 * 1000).toISOString();
  const agents = (s && s.agents) || {};
  const log = (s && s.log) || [];
  return TEAM.map(m => {
    const a = agents[m.id] || {};
    const pres = officePresence(a.state);
    const latest = latestLogFor(log, m.id);
    const bubble = bubbleText(latest);
    const detail = detailLine(a, latest, pres.involved) || (pres.involved ? (a.task || '') : 'รออยู่ที่ห้องพัก');
    const o = {
      agentId: m.id, name: m.name, isMain: !!m.main,
      state: pres.state, detail, updated_at: now, area: pres.area, involved: pres.involved,
      source: 'loop-bridge', joinKey: null,
      authStatus: 'approved', authApprovedAt: now, authExpiresAt: far, lastPushAt: now,
    };
    if (latest) {
      if (latest.speech) o.lastSpeech = latest.speech;
      if (latest.title) o.lastTitle = latest.title;
      if (latest.skill) o.lastSkill = latest.skill;
      if (latest.cmd) o.lastCmd = latest.cmd;
      if (latest.to) o.lastTo = latest.to;
      if (latest.kind) o.lastKind = latest.kind;
      if (latest.file) o.lastFile = latest.file;
      if (latest.action) o.lastAction = latest.action;
      if (latest.detail) o.lastDetail = latest.detail;
      if (latest.msg) o.lastMsg = latest.msg;
    }
    if (bubble) o.bubbleText = bubble;
    if (m.avatar) o.avatar = m.avatar;
    return o;
  });
}

function tick() {
  const s = read();
  if (!s) return;
  try { fs.mkdirSync(STAR, { recursive: true }); } catch (e) {}
  const agents = build(s);
  fs.writeFileSync(AGENTS_FILE, JSON.stringify(agents, null, 2));
  const main = agents.find(a => a.isMain) || agents[0];
  const project = (s.project || '').trim();
  const log = Array.isArray(s.log) ? s.log : [];
  const latest = log.length ? log[log.length - 1] : null;
  const statusDetail = statusBarLine(latest) || main.detail || (s.task || 'Waiting...');
  fs.writeFileSync(STATE_FILE, JSON.stringify({
    state: main.state,
    detail: statusDetail.slice(0, 240),
    progress: 0,
    updated_at: main.updated_at,
    officeName: project ? (project + ' · office') : 'AI Agent Software Team',
  }, null, 2));
  fs.writeFileSync(ACTIVITY_FILE, JSON.stringify({
    project: s.project || '',
    task: s.task || '',
    loop: s.loop || 1,
    updatedAt: s.updatedAt || new Date().toISOString(),
    log: log.slice(-500),
  }, null, 2));
}

tick();
if (!process.argv.includes('--once')) setInterval(tick, 5000);
