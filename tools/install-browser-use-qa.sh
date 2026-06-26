#!/usr/bin/env zsh
# Install browser-use QA skill → ~/.agents/skills/loom-qa (Hermes: qa-browser symlink).
# Source: https://github.com/browser-use/browser-use/tree/main/skills/loom-qa
set -euo pipefail

DEST="${HOME}/.agents/skills/loom-qa"
mkdir -p "${HOME}/.agents/skills"

if command -v npx >/dev/null 2>&1; then
  echo "== browser-use qa via npx skills =="
  npx --yes skills add qa
elif command -v uv >/dev/null 2>&1; then
  echo "== browser-harness CLI (browser-use runtime) =="
  uv tool install "git+https://github.com/browser-use/browser-harness" 2>/dev/null || true
  mkdir -p "$DEST/references"
  curl -fsSL "https://raw.githubusercontent.com/browser-use/browser-use/main/skills/loom-qa/SKILL.md" \
    -o "$DEST/SKILL.md"
else
  echo "== curl browser-use qa skill (no npx/uv) =="
  mkdir -p "$DEST/references"
  curl -fsSL "https://raw.githubusercontent.com/browser-use/browser-use/main/skills/loom-qa/SKILL.md" \
    -o "$DEST/SKILL.md"
fi

if [ -f "$DEST/SKILL.md" ]; then
  echo "  ✓ qa skill → $DEST/SKILL.md"
else
  echo "  ✗ install failed — try: npx skills add qa" >&2
  exit 1
fi

# ponytail: minimal check — skill file exists and mentions browser
grep -q browser "$DEST/SKILL.md" || { echo "  ✗ SKILL.md looks wrong" >&2; exit 1; }
echo "Done. Hermes users: zsh tools/install-hermes-skills.sh  (symlinks as qa-browser)"
