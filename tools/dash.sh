#!/usr/bin/env zsh
# dash.sh — talk to the ONE central dashboard that lives in the blueprint (Base).
# The dashboard is NEVER copied into a project: every project/session reports to the same
# Base board, and each line is tagged with the project name so you can tell work apart.
#
#   zsh tools/dash.sh serve              # open the central dashboard (Star-Office)
#   zsh tools/dash.sh simple [PORT]      # open the zero-dep fallback board
#   zsh tools/dash.sh <status-cmd...>    # forward to agent-status.js, auto-tagged with project
#                                         #   e.g. reset "<task>" | set be work "..." | loop 2 | log who "msg"
#   zsh tools/dash.sh where              # print the resolved Base dashboard path
#
# Base resolution:  $LOOP_BASE env  >  ~/.loop-base file  >  this tool's own repo (if it has the dashboard)
set -euo pipefail
SELF_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

BASE="${LOOP_BASE:-}"
[ -n "$BASE" ] || { [ -f "$HOME/.loop-base" ] && BASE="$(head -n1 "$HOME/.loop-base")"; }
[ -n "$BASE" ] || BASE="$SELF_ROOT"
BASE="${BASE%/}"
DASH="$BASE/agent-dashboard"

if [ ! -d "$DASH" ]; then
  echo "central dashboard not found at: $DASH" >&2
  echo "run 'zsh tools/deploy.sh' inside the blueprint once to register it (writes ~/.loop-base)." >&2
  exit 1
fi

# Project name for this call: local loop.config.json (cwd) if present, else "(blueprint)".
project=""
if [ -f "loop.config.json" ]; then
  project="$(node "$SELF_ROOT/tools/cfg.js" get project 2>/dev/null || true)"
fi
[ -n "$project" ] || project="(unknown)"

cmd="${1:-}"
case "$cmd" in
  serve)        shift; exec zsh "$DASH/serve.sh" "$@" ;;
  simple)       shift; exec zsh "$DASH/serve.sh" simple "$@" ;;
  where)        echo "$DASH"; exit 0 ;;
  "" )          echo "usage: dash.sh serve|simple|where| <status-cmd...>" >&2; exit 1 ;;
  *)            exec env LOOP_PROJECT="$project" node "$DASH/agent-status.js" "$@" ;;
esac
