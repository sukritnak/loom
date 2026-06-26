#!/usr/bin/env zsh
# Deploy the agent team from this blueprint to your platforms (run once).
# Syncs agents to Claude Code + Hermes (see sync-agents.sh), then opens the dashboard.
# Usage: zsh tools/deploy.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Register THIS blueprint as the central dashboard home so any project can find it
# (tools/dash.sh reads ~/.loop-base). The dashboard is never copied into projects.
printf '%s\n' "$ROOT" > "$HOME/.loop-base"

zsh tools/sync-agents.sh

if [ "${DEPLOY_SKIP_CC_HOOKS:-}" != 1 ]; then
  zsh tools/install-dash-hooks.sh
else
  echo "  (skipped dashboard hooks — DEPLOY_SKIP_CC_HOOKS=1)"
fi

if [ "${DEPLOY_SKIP_L3_HOOKS:-}" != 1 ]; then
  zsh tools/install-l3-hooks.sh
else
  echo "  (skipped L3 hooks — DEPLOY_SKIP_L3_HOOKS=1)"
fi

if [ "${DEPLOY_SKIP_EXTERNAL_SKILLS:-}" != 1 ]; then
  echo "== recommended external skills =="
  zsh tools/install-external-skills.sh
  if command -v hermes >/dev/null 2>&1 || [ -d "$HOME/.hermes" ]; then
    zsh tools/install-hermes-skills.sh >/dev/null   # refresh Hermes symlinks
    echo "  ✓ Hermes external symlinks refreshed"
  else
    echo "  - Hermes skills  → not detected (skipped)"
  fi
else
  echo "  (skipped external skills — DEPLOY_SKIP_EXTERNAL_SKILLS=1)"
fi

cat <<'TXT'

For Cursor personas (optional): Settings → Custom Modes → add one per agent,
pasting the body of each .claude/agents/*.md as the instructions.

Next: start a project →  Use loom-start  (or  zsh tools/loom-start.sh)
TXT

echo "== opening central dashboard =="
( zsh "$ROOT/agent-dashboard/serve.sh" >/dev/null 2>&1 & )
echo "  http://localhost:19000"
