#!/usr/bin/env zsh
# install-dash-hooks.sh — auto-sync agent activity to the central dashboard (all platforms).
#   Claude Code → ~/.claude/settings.json
#   Cursor      → ~/.cursor/hooks.json
# Usage: zsh tools/install-dash-hooks.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "== Loom dashboard hooks =="
zsh "$ROOT/tools/install-cc-hooks.sh"
zsh "$ROOT/tools/install-cursor-hooks.sh"
echo ""
echo "Done. Agent file edits, shell commands, and reports mirror to http://localhost:19000"
echo "(run zsh tools/dash.sh serve once). Hermes / manual chat still benefit from explicit dash.sh calls."
