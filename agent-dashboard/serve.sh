#!/usr/bin/env bash
# Serve the live dashboard. Run from the folder that contains index.html + agent-status.js.
# Idempotent: if a server is already up on PORT, it just opens the browser and exits — so it's
# safe to call repeatedly (e.g. from `make deploy` or at loop-orch start).
cd "$(dirname "$0")" || exit 1
PORT="${1:-8787}"
URL="http://localhost:$PORT"

open_browser() {
  ( command -v open >/dev/null && open "$URL" ) 2>/dev/null || \
  ( command -v xdg-open >/dev/null && xdg-open "$URL" ) 2>/dev/null || true
}

# already serving? just focus the browser and stop here.
if (exec 3<>"/dev/tcp/localhost/$PORT") 2>/dev/null; then
  exec 3>&- 3<&-
  echo "dashboard already running → $URL"
  open_browser
  exit 0
fi

# create an empty status file if missing, so the dashboard connects immediately
[ -f status.json ] || node agent-status.js reset "" >/dev/null 2>&1

echo "AI Agent Office dashboard → $URL"
echo "(serving $(pwd)). Ctrl+C to stop."
open_browser
python3 -m http.server "$PORT"
