#!/usr/bin/env zsh
# install-cc-hooks.sh — wire Claude Code hooks → Loom dashboard (cc-dash-bridge.js).
# Merges into ~/.claude/settings.json without removing your other hooks.
# Replaces stale dash-bridge paths (e.g. after moving the Loom repo).
# Skips silently when Claude Code is not installed.
# Usage: zsh tools/install-cc-hooks.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE="$ROOT/agent-dashboard/dash-bridge.js"
CC_BRIDGE="$ROOT/agent-dashboard/cc-dash-bridge.js"
SETTINGS="$HOME/.claude/settings.json"

if ! command -v claude >/dev/null 2>&1 && [[ ! -f "$SETTINGS" ]]; then
  echo "  (skip Claude Code hooks — \`claude\` not found; install Claude Code then re-run)"
  exit 0
fi

chmod +x "$BRIDGE" "$CC_BRIDGE"

node -e "
const fs = require('fs');
const ccBridge = process.argv[1];
const settingsPath = process.argv[2];
const entry = { type: 'command', command: 'node ' + JSON.stringify(ccBridge), async: true };
const hookBlock = (matcher) => ({
  ...(matcher ? { matcher } : {}),
  hooks: [entry],
});
const loomHooks = {
  SubagentStart: [hookBlock()],
  PostToolUse: [hookBlock('Edit|Write|StrReplace|Delete|Bash')],
  SubagentStop: [hookBlock()],
  Stop: [hookBlock()],
};
const isLoomDash = (h) => /dash-bridge|cc-dash-bridge/.test(String(h && h.command || ''));

let s = {};
try { s = JSON.parse(fs.readFileSync(settingsPath, 'utf8')); } catch (e) {}
s.hooks = s.hooks || {};

// Drop broken / old Loom dashboard hook entries, then re-append fresh blocks.
for (const ev of Object.keys(s.hooks)) {
  const arr = s.hooks[ev];
  if (!Array.isArray(arr)) continue;
  s.hooks[ev] = arr
    .map((block) => ({
      ...block,
      hooks: (block.hooks || []).filter((h) => !isLoomDash(h)),
    }))
    .filter((block) => (block.hooks || []).length > 0);
}
for (const [ev, blocks] of Object.entries(loomHooks)) {
  s.hooks[ev] = [...(s.hooks[ev] || []), ...blocks];
}

fs.mkdirSync(require('path').dirname(settingsPath), { recursive: true });
fs.writeFileSync(settingsPath, JSON.stringify(s, null, 2) + '\n');
console.log('  ✓ Claude Code hooks → dashboard bridge');
console.log('    ' + ccBridge);
" "$CC_BRIDGE" "$SETTINGS"

mkdir -p "$HOME/.loop-dash"
echo "  ✓ state dir ~/.loop-dash"
echo ""
echo "Restart Claude Code (or start a new session) so hooks load."
echo "Hooks bridge only after Use loop-start / loop-orch (or a Loom sub-agent starts)."
