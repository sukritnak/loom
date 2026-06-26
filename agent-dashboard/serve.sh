#!/usr/bin/env zsh
# Launch the Star-Office pixel dashboard (vendored) + the loop->office bridge.
# Idempotent: if the office is already up on PORT, it just opens the browser and exits —
# safe to call repeatedly (e.g. from deploy.sh or at loom-orch start).
#
#   zsh serve.sh                 # start on :19000 (override with STAR_BACKEND_PORT)
set -euo pipefail
cd "$(dirname "$0")" || exit 1
DASH="$(pwd)"
STAR="$DASH/star-office"

# Register this blueprint as the central dashboard home (so any project's tools/dash.sh finds it).
printf '%s\n' "$(cd "$DASH/.." && pwd)" > "$HOME/.loop-base" 2>/dev/null || true

open_browser(){ ( command -v open >/dev/null && open "$1" ) 2>/dev/null || ( command -v xdg-open >/dev/null && xdg-open "$1" ) 2>/dev/null || true; }
up(){ nc -z 127.0.0.1 "$1" 2>/dev/null || lsof -iTCP:"$1" -sTCP:LISTEN -P -n >/dev/null 2>&1; }

PORT="${STAR_BACKEND_PORT:-19000}"; URL="http://localhost:$PORT"
if up "$PORT"; then echo "Star-Office already running → $URL"; open_browser "$URL"; exit 0; fi

# seed status.json so the bridge has something to mirror
[ -f status.json ] || node agent-status.js reset "" >/dev/null 2>&1 || true

# venv + flask + pillow (Go Home / image resize). Recreate if path moved (bad shebang).
VENV="$STAR/.venv"; PY="$VENV/bin/python"
venv_ok() { [ -x "$PY" ] && "$PY" -c 'import sys' 2>/dev/null; }
if ! venv_ok; then
  echo "recreating star-office venv (missing or moved from old path)…"
  rm -rf "$VENV"
  python3 -m venv "$VENV"
fi
"$PY" -m pip install -q --disable-pip-version-check flask pillow >/dev/null

# loop -> office bridge: seed once, then keep refreshing in the background
node star-office-bridge.js --once >/dev/null 2>&1 || true
node star-office-bridge.js >/dev/null 2>&1 &
BRIDGE=$!
trap 'kill "$BRIDGE" 2>/dev/null || true' EXIT INT TERM

echo "Star-Office dashboard → $URL   (bridge pid $BRIDGE). Ctrl+C to stop."
open_browser "$URL"
STAR_BACKEND_PORT="$PORT" "$PY" "$STAR/backend/app.py"
