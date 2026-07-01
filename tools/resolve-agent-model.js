#!/usr/bin/env node
/*
 * Resolve Loom agent platform + model from loop.config.json and runtime.
 *
 *   node tools/resolve-agent-model.js              -> JSON { platform, model, source }
 *   node tools/resolve-agent-model.js detect       -> cursor | claude | hermes | unknown
 *   node tools/resolve-agent-model.js get          -> resolved model id for current runtime
 *   node tools/resolve-agent-model.js get cursor   -> model id for a specific platform
 *   node tools/resolve-agent-model.js list         -> all platforms + model options (JSON)
 *   node tools/resolve-agent-model.js list cursor  -> model options for one platform
 *   node tools/resolve-agent-model.js validate cursor claude-sonnet-5-thinking-medium
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const base = process.env.LOOM_BASE || (() => {
  try { return fs.readFileSync(path.join(os.homedir(), '.loop-base'), 'utf8').trim(); } catch { return ''; }
})();
const catalogPath = path.join(base || path.join(__dirname), 'agent-models.json');
const catalog = JSON.parse(fs.readFileSync(
  fs.existsSync(catalogPath) ? catalogPath : path.join(__dirname, 'agent-models.json'),
  'utf8',
));

const allowed = Object.fromEntries(
  Object.entries(catalog.models).map(([p, opts]) => [p, new Set(opts.map((o) => o.id))]),
);

function detectPlatform() {
  if (process.env.CURSOR_VERSION || process.env.CURSOR_TRACE_ID || process.env.CURSOR_SESSION_ID) return 'cursor';
  if (process.env.HERMES_HOME || process.env.HERMES_AGENT_ROOT || process.env.HERMES_SESSION_ID) return 'hermes';
  if (process.env.CLAUDE_CODE_ENTRYPOINT || process.env.CLAUDE_CODE_SSE_PORT || process.env.CLAUDE_CODE_CONTAINER) return 'claude';
  if (process.env.TERM_PROGRAM === 'Cursor') return 'cursor';
  if (process.env.TERM_PROGRAM === 'vscode' && fs.existsSync(path.join(os.homedir(), '.cursor'))) return 'cursor';
  if (commandExists('claude') && !commandExists('cursor') && process.env.TERM_PROGRAM !== 'Cursor') return 'claude';
  if (commandExists('hermes') && process.env.HERMES_INVOKE) return 'hermes';
  return 'unknown';
}

function commandExists(cmd) {
  try {
    const r = require('child_process').spawnSync('command', ['-v', cmd], { stdio: 'ignore' });
    return r.status === 0;
  } catch { return false; }
}

function findConfig(start = process.cwd()) {
  let dir = path.resolve(start);
  for (;;) {
    const f = path.join(dir, 'loop.config.json');
    if (fs.existsSync(f)) return JSON.parse(fs.readFileSync(f, 'utf8'));
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  const active = path.join(base, '.active-project');
  if (base && fs.existsSync(active)) {
    const dest = fs.readFileSync(active, 'utf8').trim();
    const f = path.join(dest, 'loop.config.json');
    if (fs.existsSync(f)) return JSON.parse(fs.readFileSync(f, 'utf8'));
  }
  return {};
}

function normalizeConfig(cfg) {
  const out = { ...cfg };
  if (!out.agent_platform) {
    out.agent_platform = out.model && !out.agent_models ? 'cursor' : 'auto';
  }
  if (!out.agent_models && typeof out.agent_model === 'string') {
    out.agent_models = { [out.agent_platform]: out.agent_model };
  }
  if (!out.agent_models) out.agent_models = {};
  if (out.model && !out.agent_models.cursor) out.agent_models.cursor = out.model;
  if (!out.agent_models.cursor) out.agent_models.cursor = catalog.defaults.cursor;
  if (!out.agent_models.claude) out.agent_models.claude = catalog.defaults.claude;
  if (!out.agent_models.hermes) out.agent_models.hermes = catalog.defaults.hermes;
  return out;
}

function validate(platform, model) {
  const ids = allowed[platform];
  if (!ids) throw new Error(`unknown platform: ${platform}`);
  if (!ids.has(model)) throw new Error(`unknown model for ${platform}: ${model}`);
}

function resolve(platformHint) {
  const cfg = normalizeConfig(findConfig());
  const detected = platformHint && platformHint !== 'unknown' ? platformHint : detectPlatform();
  const platform = cfg.agent_platform === 'auto'
    ? (detected !== 'unknown' ? detected : 'cursor')
    : cfg.agent_platform;
  const model = cfg.agent_models[platform] || catalog.defaults[platform];
  validate(platform, model);
  return {
    platform,
    model,
    detected,
    agent_platform: cfg.agent_platform,
    agent_models: cfg.agent_models,
    source: cfg.agent_platform === 'auto' ? 'auto+detect' : 'config',
  };
}

const [, , cmd, arg, arg2] = process.argv;
let out = '';
try {
  switch (cmd) {
    case 'detect':
      out = detectPlatform();
      break;
    case 'get':
      out = resolve(arg || detectPlatform()).model;
      break;
    case 'list':
      if (arg && catalog.models[arg]) {
        out = JSON.stringify(catalog.models[arg], null, 2);
      } else {
        out = JSON.stringify({ platforms: catalog.platforms, defaults: catalog.defaults, models: catalog.models }, null, 2);
      }
      break;
    case 'validate':
      validate(arg, arg2);
      out = 'ok';
      break;
  default:
      out = JSON.stringify(resolve(arg || detectPlatform()), null, 2);
  }
} catch (e) {
  console.error(e.message || e);
  process.exit(1);
}
process.stdout.write(out === '' ? '' : String(out) + (cmd === 'validate' || cmd === 'detect' || cmd === 'get' ? '\n' : ''));
