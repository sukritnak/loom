#!/usr/bin/env node
/*
 * star-office-bridge.js — mirror the loop's status.json into the vendored Star-Office-UI.
 *
 * Reads  ./status.json            (written by agent-status.js — the agent-facing API)
 * Writes ./star-office/state.json        (main "star" state, served at /status)
 *        ./star-office/agents-state.json (full team, served at /agents)
 *
 * We own these files locally, so we seed them directly and skip Star-Office's
 * join-key / auth / push flow entirely. Refreshes every 5s so the office never
 * marks our agents "offline" (its /agents cleanup flips approved->offline after 5 min).
 *
 *   node star-office-bridge.js          run forever (5s loop)
 *   node star-office-bridge.js --once   write once and exit
 */
const fs = require('fs');
const path = require('path');

const DIR = __dirname;
const SRC = path.join(DIR, 'status.json');
const STAR = path.join(DIR, 'star-office');
const AGENTS_FILE = path.join(STAR, 'agents-state.json');
const STATE_FILE = path.join(STAR, 'state.json');

// orch is the main "star"; the rest are guests (avatars cycle through guest_role_1..6).
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
// our loop state -> Star-Office state (work=writing zone, fix=bug zone, done/idle=breakroom)
const MAP = { work: 'writing', fix: 'error', done: 'idle', idle: 'idle' };
const AREA = { writing: 'writing', error: 'error', idle: 'breakroom' };

function read() {
  try { return JSON.parse(fs.readFileSync(SRC, 'utf8')); } catch (e) { return null; }
}

function build(s) {
  const now = new Date().toISOString();
  const far = new Date(Date.now() + 24 * 3600 * 1000).toISOString();
  const agents = (s && s.agents) || {};
  return TEAM.map(m => {
    const a = agents[m.id] || {};
    const st = MAP[a.state] || 'idle';
    const detail = a.task || (st === 'idle' ? 'รออยู่ที่โต๊ะ' : '');
    const o = {
      agentId: m.id, name: m.name, isMain: !!m.main,
      state: st, detail, updated_at: now, area: AREA[st] || 'breakroom',
      source: 'loop-bridge', joinKey: null,
      authStatus: 'approved', authApprovedAt: now, authExpiresAt: far, lastPushAt: now,
    };
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
  fs.writeFileSync(STATE_FILE, JSON.stringify({
    state: main.state,
    detail: main.detail || (s.task || 'Waiting...'),
    progress: 0,
    updated_at: main.updated_at,
    // plaque on the office = which project is running right now (central board, many projects)
    officeName: project ? (project + ' · office') : 'AI Agent Office',
  }, null, 2));
}

tick();
if (!process.argv.includes('--once')) setInterval(tick, 5000);
