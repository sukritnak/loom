#!/usr/bin/env bash
# Deploy the agent team from this blueprint to your platforms (run once).
#   - Claude Code : copies the 8 subagents to ~/.claude/agents/ (available in every project)
#   - Hermes      : regenerates SKILL.md and installs the team into ~/.hermes/skills/
#   - Cursor      : prints the manual step (Custom Modes can't be scripted)
# Usage: bash tools/deploy.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== 1/3 Claude Code =="
mkdir -p "$HOME/.claude/agents"
cp -f .claude/agents/*.md "$HOME/.claude/agents/"
echo "  copied $(ls .claude/agents/*.md | wc -l | tr -d ' ') agents → ~/.claude/agents/"

echo "== 2/3 Hermes =="
if command -v hermes >/dev/null 2>&1 || [ -d "$HOME/.hermes" ]; then
  bash tools/to-hermes-skills.sh >/dev/null
  bash tools/install-hermes-skills.sh
else
  echo "  hermes not detected — skipped. (install it, then: bash tools/install-hermes-skills.sh)"
fi

echo "== 3/3 Cursor (manual) =="
cat <<'TXT'
  Cursor reads the same files in .claude/agents/ when you open this folder.
  For dedicated personas: Settings → Custom Modes → add one per agent,
  pasting the body of each .claude/agents/*.md as the instructions.

Optional external skills (for richer reviews / bundles):
  npx skills add solid ponytail ponytail-review perf-lighthouse \
    postgres-best-practices docker-containerization threejs-animation qa

Next: start a project →  bash tools/new-project.sh
TXT

echo "== opening dashboard =="
( bash "$ROOT/agent-dashboard/serve.sh" >/dev/null 2>&1 & )
echo "  http://localhost:8787"
