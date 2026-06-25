#!/usr/bin/env zsh
# install-cursor-hooks.sh — wire Cursor user hooks → Loom dashboard (dash-bridge.js).
# Merges into ~/.cursor/hooks.json without removing your other hooks.
# Skips silently when Cursor is not installed.
# Usage: zsh tools/install-cursor-hooks.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE="$ROOT/agent-dashboard/dash-bridge.js"
SETTINGS="$HOME/.cursor/hooks.json"

if ! command -v cursor >/dev/null 2>&1 && [[ ! -d "$HOME/.cursor" ]]; then
  echo "  (skip Cursor hooks — Cursor not detected; install Cursor then re-run)"
  exit 0
fi

chmod +x "$ROOT/agent-dashboard/dash-bridge.js" "$ROOT/agent-dashboard/cc-dash-bridge.js"

node -e "
const fs = require('fs');
const bridge = process.argv[1];
const settingsPath = process.argv[2];
const cmd = (ev) => 'node ' + JSON.stringify(bridge) + ' ' + ev;
const entry = (ev, matcher) => {
  const o = { command: cmd(ev) };
  if (matcher) o.matcher = matcher;
  return o;
};
const loomHooks = {
  subagentStart: [entry('subagentStart')],
  subagentStop: [entry('subagentStop')],
  postToolUse: [entry('postToolUse', 'Shell|Write|StrReplace|Delete|Edit|Bash')],
  afterFileEdit: [entry('afterFileEdit')],
  afterTabFileEdit: [entry('afterTabFileEdit')],
  afterShellExecution: [entry('afterShellExecution')],
  afterAgentResponse: [entry('afterAgentResponse', 'AgentResponse')],
  stop: [entry('stop')],
};
const isLoomDash = (h) => /dash-bridge|cc-dash-bridge/.test(String(h && h.command || ''));

let s = { version: 1, hooks: {} };
try { s = JSON.parse(fs.readFileSync(settingsPath, 'utf8')); } catch (e) {}
s.version = s.version || 1;
s.hooks = s.hooks || {};

for (const ev of Object.keys(s.hooks)) {
  const arr = s.hooks[ev];
  if (!Array.isArray(arr)) continue;
  s.hooks[ev] = arr.filter((h) => !isLoomDash(h));
  if (!s.hooks[ev].length) delete s.hooks[ev];
}
for (const [ev, blocks] of Object.entries(loomHooks)) {
  s.hooks[ev] = [...(s.hooks[ev] || []), ...blocks];
}
fs.mkdirSync(require('path').dirname(settingsPath), { recursive: true });
fs.writeFileSync(settingsPath, JSON.stringify(s, null, 2) + '\n');
console.log('  ✓ Cursor hooks → dashboard bridge');
console.log('    ' + bridge);
" "$BRIDGE" "$SETTINGS"

mkdir -p "$HOME/.loop-dash"
echo "  ✓ state dir ~/.loop-dash"
echo ""
echo "Restart Cursor (or reload hooks) so ~/.cursor/hooks.json is picked up."
echo "Dashboard still needs loop.config.json in cwd or a parent folder for project tags."
