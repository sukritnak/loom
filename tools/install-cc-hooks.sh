#!/usr/bin/env zsh
# install-cc-hooks.sh — wire Claude Code hooks → Loom dashboard (cc-dash-bridge.js).
# Merges into ~/.claude/settings.json without removing your other hooks.
# Usage: zsh tools/install-cc-hooks.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE="$ROOT/agent-dashboard/dash-bridge.js"
CC_BRIDGE="$ROOT/agent-dashboard/cc-dash-bridge.js"
SETTINGS="$HOME/.claude/settings.json"
chmod +x "$BRIDGE" "$CC_BRIDGE"

node -e "
const fs = require('fs');
const bridge = process.argv[1];
const settingsPath = process.argv[2];
const entry = { type: 'command', command: 'node ' + JSON.stringify(bridge), async: true };
const hookBlock = (matcher) => ({
  ...(matcher ? { matcher } : {}),
  hooks: [entry],
});
const loomHooks = {
  SubagentStart: [hookBlock()],
  PostToolUse: [hookBlock('Edit|Write'), hookBlock('Bash')],
  SubagentStop: [hookBlock()],
  Stop: [hookBlock()],
};
let s = {};
try { s = JSON.parse(fs.readFileSync(settingsPath, 'utf8')); } catch (e) {}
s.hooks = s.hooks || {};
const marker = 'dash-bridge.js';
function hasBridge(arr) {
  return Array.isArray(arr) && arr.some(b =>
    (b.hooks || []).some(h => String(h.command || '').includes(marker))
  );
}
for (const [ev, blocks] of Object.entries(loomHooks)) {
  if (hasBridge(s.hooks[ev])) continue;
  s.hooks[ev] = [...(s.hooks[ev] || []), ...blocks];
}
fs.mkdirSync(require('path').dirname(settingsPath), { recursive: true });
fs.writeFileSync(settingsPath, JSON.stringify(s, null, 2) + '\n');
console.log('  ✓ Claude Code hooks → dashboard bridge');
console.log('    ' + bridge);
" "$BRIDGE" "$SETTINGS"

mkdir -p "$HOME/.loop-dash"
echo "  ✓ state dir ~/.loop-dash"
echo ""
echo "Restart Claude Code (or start a new session) so hooks load."
echo "Dashboard still needs loop.config.json in cwd or a parent folder for project tags."
