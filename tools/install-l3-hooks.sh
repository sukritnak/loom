#!/usr/bin/env zsh
# install-l3-hooks.sh — auto-approve Claude Code prompts when loop.config autonomy is L3.
# Merges PermissionRequest hook into ~/.claude/settings.json (keeps your other hooks).
# Skips silently when Claude Code is not installed.
# Usage: zsh tools/install-l3-hooks.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/agent-dashboard/l3-permission-hook.js"
SETTINGS="$HOME/.claude/settings.json"

if ! command -v claude >/dev/null 2>&1 && [[ ! -f "$SETTINGS" ]]; then
  echo "  (skip L3 hooks — Claude Code not detected)"
  exit 0
fi

chmod +x "$HOOK"

node -e "
const fs = require('fs');
const hook = process.argv[1];
const settingsPath = process.argv[2];
const entry = { type: 'command', command: 'node ' + JSON.stringify(hook) };
const block = { hooks: [entry] };
const marker = 'l3-permission-hook.js';
let s = {};
try { s = JSON.parse(fs.readFileSync(settingsPath, 'utf8')); } catch (e) {}
s.hooks = s.hooks || {};
const arr = s.hooks.PermissionRequest || [];
if (arr.some(b => (b.hooks || []).some(h => String(h.command || '').includes(marker)))) {
  console.log('  ✓ L3 permission hook already installed');
  process.exit(0);
}
s.hooks.PermissionRequest = [block, ...arr];
fs.mkdirSync(require('path').dirname(settingsPath), { recursive: true });
fs.writeFileSync(settingsPath, JSON.stringify(s, null, 2) + '\n');
console.log('  ✓ L3 permission hook → auto-allow when autonomy=L3');
console.log('    ' + hook);
" "$HOOK" "$SETTINGS"

echo ""
echo "Restart Claude Code. L3 auto-yes applies when:"
echo "  · loop.config.json has \"autonomy\": \"L3\""
echo "  · cwd is control folder OR a service path in that config"
echo "  · safety denylist still blocks force-push, rm -rf, .env, deploy, …"
