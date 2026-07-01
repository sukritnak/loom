#!/usr/bin/env zsh
# Auto-install dashboard Gemini image skill (venv + deps). Idempotent.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ROOT/agent-dashboard/skills/gemini-image-generate"

if [ ! -f "$SKILL/scripts/gemini_image_generate.py" ]; then
  echo "  ~ gemini-image-generate: script not in repo" >&2
  exit 0
fi

zsh "$SKILL/install.sh"
