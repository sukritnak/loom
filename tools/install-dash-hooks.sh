#!/usr/bin/env zsh
# install-dash-hooks.sh — auto-sync agent activity to the central dashboard (all platforms).
#   Claude Code → ~/.claude/settings.json  (skip if no claude)
#   Cursor      → ~/.cursor/hooks.json     (skip if no cursor)
#   Hermes      → ~/.hermes/config.yaml    (skip if no hermes)
# Usage: zsh tools/install-dash-hooks.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "== Loom dashboard hooks =="
zsh "$ROOT/tools/install-cc-hooks.sh" || true
zsh "$ROOT/tools/install-cursor-hooks.sh" || true
zsh "$ROOT/tools/install-hermes-hooks.sh" || true
mkdir -p "$HOME/.loop-dash"
echo ""
echo "Done (installed only for platforms detected on this machine)."
echo "Agent activity mirrors to http://localhost:19000 when hooks are active (zsh tools/dash.sh serve)."
