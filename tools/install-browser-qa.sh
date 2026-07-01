#!/usr/bin/env zsh
# Browser QA stack — idempotent; safe on every git pull / refresh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "== browser QA stack =="
zsh "$ROOT/tools/ensure-loom-home.sh" >/dev/null
zsh "$ROOT/tools/install-chrome-devtools-mcp.sh"

if [ -f "${HOME}/.agents/skills/qa/SKILL.md" ] || [ -f "${HOME}/.agents/skills/loom-qa/SKILL.md" ]; then
  echo "  ✓ qa-browser skill present"
else
  zsh "$ROOT/tools/install-browser-use-qa.sh"
fi

echo "Done. Default qa_browser=auto → local-cdp when MCP is installed."
