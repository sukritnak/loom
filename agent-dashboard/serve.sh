#!/usr/bin/env zsh
# Launch the Star-Office pixel dashboard (vendored) + the loop->office bridge.
# Idempotent: if the office is already up on PORT, it just opens the browser and exits —
# safe to call repeatedly (e.g. from deploy.sh or at loop-orch start).
#
#   zsh serve.sh                 # start on :19000 (override with STAR_BACKEND_PORT)
#   zsh serve.sh simple [PORT]   # fall back to the old zero-dep single-file dashboard
set -euo pipefail
cd "$(dirname "$0")" || exit 1
DASH="$(pwd)"
STAR="$DASH/star-office"

# Register this blueprint as the central dashboard home (so any project's tools/dash.sh finds it).
printf '%s\n' "$(cd "$DASH/.." && pwd)" > "$HOME/.loop-base" 2>/dev/null || true

open_browser(){ ( command -v open >/dev/null && open "$1" ) 2>/dev/null || ( command -v xdg-open >/dev/null && xdg-open "$1" ) 2>/dev/null || true; }
up(){ nc -z 127.0.0.1 "$1" 2>/dev/null || lsof -iTCP:"$1" -sTCP:LISTEN -P -n >/dev/null 2>&1; }

# --- fallback: original zero-dep dashboard (no Python/Flask) ---
if [ "${1:-}" = "simple" ]; then
  PORT="${2:-8787}"; URL="http://localhost:$PORT"
  if up "$PORT"; then echo "dashboard already running → $URL"; open_browser "$URL"; exit 0; fi
  [ -f status.json ] || node agent-status.js reset "" >/dev/null 2>&1 || true
  echo "AI Agent Office (simple) → $URL  — Ctrl+C to stop."
  open_browser "$URL"
  exec python3 -m http.server "$PORT"
fi

# --- default: Star-Office pixel dashboard ---
PORT="${STAR_BACKEND_PORT:-19000}"; URL="http://localhost:$PORT"
if up "$PORT"; then echo "Star-Office already running → $URL"; open_browser "$URL"; exit 0; fi

# seed status.json so the bridge has something to mirror
[ -f status.json ] || node agent-status.js reset "" >/dev/null 2>&1 || true

# one-time: python venv + flask (pillow is optional and skipped on purpose)
VENV="$STAR/.venv"; PY="$VENV/bin/python"
if [ ! -x "$PY" ]; then
  echo "first run: creating venv + installing flask (one-time)…"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q --disable-pip-version-check flask >/dev/null
fi

# loop -> office bridge: seed once, then keep refreshing in the background
node star-office-bridge.js --once >/dev/null 2>&1 || true
node star-office-bridge.js >/dev/null 2>&1 &
BRIDGE=$!
trap 'kill "$BRIDGE" 2>/dev/null || true' EXIT INT TERM

echo "Star-Office dashboard → $URL   (bridge pid $BRIDGE). Ctrl+C to stop."
open_browser "$URL"
STAR_BACKEND_PORT="$PORT" "$PY" "$STAR/backend/app.py"
