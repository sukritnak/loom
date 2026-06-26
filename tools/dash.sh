#!/usr/bin/env zsh
# dash.sh — talk to the ONE central dashboard that lives in the blueprint (Base).
# The dashboard is NEVER copied into a project: every project/session reports to the same
# Base board, and each line is tagged with the project name so you can tell work apart.
#
#   zsh tools/dash.sh serve              # open the central dashboard (Star-Office)
#   zsh tools/dash.sh up                 # exit 0 if dashboard is listening (prints URL)
#   zsh tools/dash.sh <status-cmd...>    # forward to agent-status.js, auto-tagged with project
#                                         #   set · log · say · report · wait · delegate · skill · cmd · progress · file · event · loop · reset
#   zsh tools/dash.sh where              # print the resolved Base dashboard path
#
# Base resolution:  $LOOP_BASE env  >  ~/.loop-base file  >  this tool's own repo (if it has the dashboard)
set -euo pipefail
source "${0:A:h}/path-guard.sh"
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

# Project name: walk cwd for loop.config.json, then Base/.active-project — never "(unknown)".
project="$(node "$SELF_ROOT/tools/resolve-project.js" 2>/dev/null || true)"
project="${project//$'\n'/}"

cmd="${1:-}"
case "$cmd" in
  serve)        shift; exec zsh "$DASH/serve.sh" "$@" ;;
  up)
    PORT="${STAR_BACKEND_PORT:-19000}"
    URL="http://localhost:$PORT"
    if nc -z 127.0.0.1 "$PORT" 2>/dev/null || lsof -iTCP:"$PORT" -sTCP:LISTEN -P -n >/dev/null 2>&1; then
      echo "$URL"
      exit 0
    fi
    exit 1
    ;;
  where)        echo "$DASH"; exit 0 ;;
  "" )          echo "usage: dash.sh serve|up|where| <status-cmd...>" >&2; exit 1 ;;
  *)            exec env LOOP_PROJECT="$project" node "$DASH/agent-status.js" "$@" ;;
esac
