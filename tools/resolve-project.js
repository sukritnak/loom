#!/usr/bin/env node
/*
 * resolve-project.js — project name for dashboard tags (LOOP_PROJECT).
 * Precedence: walk cwd↑ for loop.config.json → ~/.loop-base/.active-project → "" (never "(unknown)").
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const BAD = new Set(['(unknown)', '(blueprint)', 'unknown']);

function cleanProject(name) {
  const s = String(name || '').trim();
  if (!s || BAD.has(s.toLowerCase()) || BAD.has(s)) return '';
  return s;
}

function readProjectFromDir(dir) {
  try {
    const raw = fs.readFileSync(path.join(dir, 'loop.config.json'), 'utf8');
    return cleanProject(JSON.parse(raw).project);
  } catch (e) {
    return '';
  }
}

function loopBase() {
  try {
    const b = fs.readFileSync(path.join(os.homedir(), '.loop-base'), 'utf8').trim();
    if (b && fs.existsSync(b)) return b;
  } catch (e) { /* ok */ }
  return '';
}

function resolveProject(startDir) {
  let d = path.resolve(startDir || process.cwd());
  for (let i = 0; i < 16 && d && d !== path.dirname(d); i++) {
    const p = readProjectFromDir(d);
    if (p) return p;
    d = path.dirname(d);
  }
  const base = loopBase();
  if (!base) return '';
  try {
    const active = fs.readFileSync(path.join(base, '.active-project'), 'utf8').trim();
    if (active && fs.existsSync(path.join(active, 'loop.config.json'))) {
      return readProjectFromDir(active);
    }
  } catch (e) { /* ok */ }
  return '';
}

function resolveControlDir(startDir) {
  let d = path.resolve(startDir || process.cwd());
  for (let i = 0; i < 16 && d && d !== path.dirname(d); i++) {
    if (fs.existsSync(path.join(d, 'loop.config.json'))) return d;
    d = path.dirname(d);
  }
  const base = loopBase();
  if (base) {
    try {
      const active = fs.readFileSync(path.join(base, '.active-project'), 'utf8').trim();
      if (active && fs.existsSync(path.join(active, 'loop.config.json'))) return active;
    } catch (e) { /* ok */ }
  }
  return startDir || process.cwd();
}

const expandPath = (p) => String(p || '').replace(/^~(?=$|[/\\])/, os.homedir());

function serviceRoots(controlDir) {
  try {
    const cfg = JSON.parse(fs.readFileSync(path.join(controlDir, 'loop.config.json'), 'utf8'));
    const services = Array.isArray(cfg.services) ? cfg.services : [];
    const base = expandPath(cfg.base_dir || '');
    return services.map((s) => {
      const p = expandPath(s.path);
      if (!p) return '';
      if (path.isAbsolute(p)) return path.normalize(p);
      return path.normalize(path.resolve(base || controlDir, p));
    }).filter(Boolean);
  } catch (e) {
    return [];
  }
}

/** Short path for dashboard: relative to service/control root, else basename. */
function resolveDisplayPath(fp, controlDir, cwd) {
  const raw = String(fp || '').trim();
  if (!raw) return '';
  if (raw.includes('→')) {
    const [a, b] = raw.split('→').map((s) => s.trim());
    return `${resolveDisplayPath(a, controlDir, cwd)} → ${resolveDisplayPath(b, controlDir, cwd)}`;
  }
  let abs = raw;
  if (!path.isAbsolute(raw)) {
    try { abs = path.resolve(cwd || controlDir || process.cwd(), raw); }
    catch (e) { return path.basename(raw); }
  }
  abs = path.normalize(abs);
  const roots = [...new Set([controlDir, ...serviceRoots(controlDir)].filter(Boolean))]
    .sort((a, b) => b.length - a.length);
  for (const root of roots) {
    const rel = path.relative(root, abs);
    if (rel && !rel.startsWith('..') && !path.isAbsolute(rel)) {
      return rel.split(path.sep).join('/');
    }
  }
  return path.basename(abs);
}

module.exports = { cleanProject, resolveProject, resolveControlDir, resolveDisplayPath, serviceRoots };

if (require.main === module) {
  process.stdout.write(resolveProject(process.cwd()));
}
