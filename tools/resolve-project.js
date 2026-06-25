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

module.exports = { cleanProject, resolveProject, resolveControlDir };

if (require.main === module) {
  process.stdout.write(resolveProject(process.cwd()));
}
