#!/usr/bin/env node
/*
 * l3-permission-hook.js — Claude Code PermissionRequest hook.
 * When loop.config.json autonomy is L3 and cwd is in project scope → auto-allow.
 * Safety denylist still blocks (force-push, rm -rf, .env, deploy, etc.).
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const DENY_BASH = [
  /\bgit\s+push\b[^\n]*(-f|--force)\b/,
  /\bgit\s+reset\s+--hard\b/,
  /\bgit\s+clean\s+[^\n]*-f/,
  /\brm\s+-rf\b/,
  /\bDROP\s+(DATABASE|TABLE|SCHEMA)\b/i,
  /\bTRUNCATE\s+TABLE\b/i,
  /\bcurl\b[^\n]*\|\s*(ba)?sh\b/,
  /\bwget\b[^\n]*\|\s*(ba)?sh\b/,
  /\bnpm\s+publish\b/,
  /\bdocker\s+push\b/,
  /\bwrangler\s+deploy\b/,
  /\bgh\s+release\s+create\b/,
];
const DENY_FILE = [
  /(?:^|\/)\.env(?:\.|$)/,
  /(?:^|\/)secrets?\//i,
  /\.github\/workflows\//,
  /credentials?\.json$/i,
];

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch (e) { return ''; }
}

function loopBase() {
  try {
    return fs.readFileSync(path.join(os.homedir(), '.loop-base'), 'utf8').trim();
  } catch (e) { return ''; }
}

function loadConfigAt(dir) {
  const f = path.join(dir, 'loop.config.json');
  if (!fs.existsSync(f)) return null;
  try { return { dir, cfg: JSON.parse(fs.readFileSync(f, 'utf8')) }; } catch (e) { return null; }
}

function resolveLoop(cwd) {
  let d = cwd;
  for (let i = 0; i < 14 && d && d !== path.dirname(d); i++) {
    const hit = loadConfigAt(d);
    if (hit) return hit;
    d = path.dirname(d);
  }
  const base = loopBase();
  if (base) {
    try {
      const active = fs.readFileSync(path.join(base, '.active-project'), 'utf8').trim();
      const hit = loadConfigAt(active);
      if (hit) return hit;
    } catch (e) {}
  }
  return null;
}

function inScope(cwd, controlDir, cfg) {
  const c = path.resolve(cwd);
  const root = path.resolve(controlDir);
  if (c === root || c.startsWith(root + path.sep)) return true;
  for (const s of cfg.services || []) {
    let p = s.path || '';
    if (p.startsWith('~/')) p = path.join(os.homedir(), p.slice(2));
    const abs = path.isAbsolute(p) ? p : path.join(root, p);
    const r = path.resolve(abs);
    if (c === r || c.startsWith(r + path.sep)) return true;
  }
  return false;
}

function denyBash(cmd) {
  const s = String(cmd || '');
  return DENY_BASH.some(rx => rx.test(s));
}

function denyFile(fp) {
  const s = String(fp || '').replace(/\\/g, '/');
  return DENY_FILE.some(rx => rx.test(s));
}

function out(obj) {
  process.stdout.write(JSON.stringify(obj));
}

function main() {
  let input;
  try { input = JSON.parse(readStdin() || '{}'); } catch (e) { process.exit(0); }

  const event = input.hook_event_name || '';
  if (event !== 'PermissionRequest') process.exit(0);

  const cwd = input.cwd || process.cwd();
  const hit = resolveLoop(cwd);
  if (!hit || (hit.cfg.autonomy || 'L1') !== 'L3') process.exit(0);
  if (!inScope(cwd, hit.dir, hit.cfg)) process.exit(0);

  const tool = input.tool_name || '';
  const ti = input.tool_input || {};

  if (tool === 'Bash') {
    const cmd = ti.command || '';
    if (denyBash(cmd)) {
      out({
        hookSpecificOutput: {
          hookEventName: 'PermissionRequest',
          decision: { behavior: 'deny', message: 'L3 safety denylist: blocked bash command' },
        },
      });
      process.exit(0);
    }
  }

  if (tool === 'Edit' || tool === 'Write') {
    const fp = ti.file_path || ti.filePath || '';
    if (denyFile(fp)) {
      out({
        hookSpecificOutput: {
          hookEventName: 'PermissionRequest',
          decision: { behavior: 'deny', message: 'L3 safety denylist: blocked secrets/CI/.env edit' },
        },
      });
      process.exit(0);
    }
  }

  out({
    hookSpecificOutput: {
      hookEventName: 'PermissionRequest',
      decision: { behavior: 'allow' },
    },
  });
}

main();
