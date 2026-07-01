#!/usr/bin/env zsh
# Dashboard Gemini image skill — idempotent venv + pip (.venv gitignored).
# Called by tools/install-gemini-image-skill.sh, refresh.sh, serve.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
VENV="$ROOT/.venv"
PY="$VENV/bin/python"

ready() {
  [ -x "$PY" ] && "$PY" -c 'import google.genai, PIL' 2>/dev/null
}

if ready; then
  echo "  ✓ gemini-image-generate ready"
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "  ~ gemini-image-generate: python3 not found" >&2
  exit 1
fi

if [ ! -x "$PY" ]; then
  echo "  + gemini-image-generate venv…"
  python3 -m venv "$VENV"
fi

"$PY" -m pip install -q --disable-pip-version-check -r "$ROOT/requirements.txt"
echo "  ✓ gemini-image-generate ready (set GEMINI_API_KEY for New Home / Custom Style)"
