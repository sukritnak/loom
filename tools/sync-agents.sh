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

# Claude Code (global) — only if Claude Code is present
if command -v claude >/dev/null 2>&1 || [[ -d "$HOME/.claude" ]]; then
  mkdir -p "$HOME/.claude/agents"
  # Remove stale copies (old loop-* names and orphans no longer in SRC)
  setopt null_glob 2>/dev/null || true
  rm -f "$HOME/.claude/agents"/*.md
  unsetopt null_glob 2>/dev/null || true
  cp -f "$SRC"/*.md "$HOME/.claude/agents/"
  echo "  ✓ Claude Code  → ~/.claude/agents/  ($n agents)"
else
  echo "  - Claude Code  → not detected (skipped)"
fi

# Hermes
if command -v hermes >/dev/null 2>&1 || [ -d "$HOME/.hermes" ]; then
  zsh tools/to-hermes-skills.sh >/dev/null
  zsh tools/install-hermes-skills.sh >/dev/null
  echo "  ✓ Hermes       → ~/.hermes/skills/"
else
  echo "  - Hermes       → not detected (skipped)"
fi

# Cursor Subagents (~/.cursor/agents + .cursor/agents symlinks + cache purge)
if command -v cursor >/dev/null 2>&1 || [[ -d "$HOME/.cursor" ]]; then
  zsh tools/install-cursor-subagents.sh
else
  echo "  - Cursor       → not detected (skipped)"
fi
echo "Done."
