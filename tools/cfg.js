#!/usr/bin/env node
/*
 * Read loop.config.json. Used by the scaffold/verify scripts and the agents.
 *
 *   node tools/cfg.js get <dotted.key>      -> scalar (project, mode, autonomy, base_dir)
 *   node tools/cfg.js services [fe|be]      -> TSV: id <tab> side <tab> declaredPath <tab> stack
 *   node tools/cfg.js resolved [fe|be]      -> TSV: id <tab> side <tab> ABSOLUTE_PATH <tab> stack
 *   node tools/cfg.js ids [fe|be]           -> space-separated service ids
 *   node tools/cfg.js path <id>             -> declared path
 *   node tools/cfg.js abspath <id>          -> resolved absolute path (see rules below)
 *   node tools/cfg.js base                  -> resolved base_dir (~ expanded)
 *
 * Path resolution (abspath/resolved):
 *   - absolute path  -> used as-is
 *   - relative path  -> resolved against the project root (cwd, where loop.config.json lives)
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

let cfg = {};
try { cfg = JSON.parse(fs.readFileSync('loop.config.json', 'utf8')); } catch (e) {}
const services = Array.isArray(cfg.services) ? cfg.services : [];

const expand = (p) => (p || '').replace(/^~(?=$|[/\\])/, os.homedir());
const base = expand(cfg.base_dir || '');
const get = (key) => key.split('.').reduce((a, k) => (a == null ? a : a[k]), cfg);
const find = (id) => services.find((s) => s.id === id) || {};

function abspath(id) {
  const s = find(id);
  if (!s.path) return '';
  const p = expand(s.path);
  return path.isAbsolute(p) ? p : path.resolve(process.cwd(), p);
}

const tsv = (list, p) => list.map((s) => [s.id, s.side, p(s), s.stack || ''].join('\t')).join('\n');

const [, , cmd, arg] = process.argv;
let out = '';
switch (cmd) {
  case 'get':       out = get(arg || '') ?? ''; break;
  case 'base':      out = base; break;
  case 'services':  out = tsv(arg ? services.filter(s => s.side === arg) : services, s => s.path); break;
  case 'resolved':  out = tsv(arg ? services.filter(s => s.side === arg) : services, s => abspath(s.id)); break;
  case 'ids':       out = (arg ? services.filter(s => s.side === arg) : services).map(s => s.id).join(' '); break;
  case 'path':      out = find(arg).path ?? ''; break;
  case 'abspath':   out = abspath(arg); break;
  case 'side':      out = find(arg).side ?? ''; break;
  case 'stack':     out = find(arg).stack ?? ''; break;
  default:          out = cmd ? (get(cmd) ?? '') : '';
}
process.stdout.write(out === '' ? '' : String(out) + '\n');
