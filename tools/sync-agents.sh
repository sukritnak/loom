#!/usr/bin/env zsh
# Sync agent definitions across all three platforms.
# Source of truth = .claude/agents/*.md (edit Claude Code files; everything else follows).
#   Claude Code → copies *.md to ~/.claude/agents/ (available in every project)
#   Hermes      → regenerates hermes-skills/ from source, installs to ~/.hermes/skills/
#   Cursor      → reads the project's .claude/agents/ directly (it IS the source — no copy needed)
# Usage: zsh tools/sync-agents.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SRC=".claude/agents"
ls "$SRC"/*.md >/dev/null 2>&1 || { echo "no agents in $SRC"; exit 1; }

n=$(ls "$SRC"/*.md | wc -l | tr -d ' ')
echo "== sync agents (source: $SRC, $n files) =="

# Claude Code (global)
mkdir -p "$HOME/.claude/agents"
cp -f "$SRC"/*.md "$HOME/.claude/agents/"
echo "  ✓ Claude Code  → ~/.claude/agents/  ($n agents)"

# Hermes
if command -v hermes >/dev/null 2>&1 || [ -d "$HOME/.hermes" ]; then
  zsh tools/to-hermes-skills.sh >/dev/null
  zsh tools/install-hermes-skills.sh >/dev/null
  echo "  ✓ Hermes       → ~/.hermes/skills/"
else
  echo "  - Hermes       → not detected (skipped)"
fi

# Cursor
echo "  ✓ Cursor       → reads .claude/agents/ in the project (source of truth)"
echo "Done."
