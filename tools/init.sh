#!/usr/bin/env zsh
# Initialize Loom on this machine (run once).
# Syncs agents to Claude Code + Hermes (see sync-agents.sh), then opens the dashboard.
# Usage: zsh tools/init.sh
# Also runs automatically on first ./loom or loom command (via tools/refresh.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ponytail: accept legacy DEPLOY_* / LOOM_DEPLOY_* env names
INIT_SKIP_CC_HOOKS="${INIT_SKIP_CC_HOOKS:-${DEPLOY_SKIP_CC_HOOKS:-}}"
INIT_SKIP_L3_HOOKS="${INIT_SKIP_L3_HOOKS:-${DEPLOY_SKIP_L3_HOOKS:-}}"
INIT_SKIP_EXTERNAL_SKILLS="${INIT_SKIP_EXTERNAL_SKILLS:-${DEPLOY_SKIP_EXTERNAL_SKILLS:-}}"
LOOM_INIT_NO_DASH="${LOOM_INIT_NO_DASH:-${LOOM_DEPLOY_NO_DASH:-}}"

zsh tools/refresh.sh --quiet

if [ "${INIT_SKIP_CC_HOOKS:-}" = 1 ]; then
  echo "  (skipped dashboard hooks — INIT_SKIP_CC_HOOKS=1)"
fi

if [ "${INIT_SKIP_L3_HOOKS:-}" != 1 ]; then
  zsh tools/install-l3-hooks.sh
else
  echo "  (skipped L3 hooks — INIT_SKIP_L3_HOOKS=1)"
fi

if [ "${INIT_SKIP_EXTERNAL_SKILLS:-}" != 1 ]; then
  echo "== recommended external skills =="
  zsh tools/install-external-skills.sh
  if command -v hermes >/dev/null 2>&1 || [ -d "$HOME/.hermes" ]; then
    zsh tools/install-hermes-skills.sh >/dev/null   # refresh Hermes symlinks
    echo "  ✓ Hermes external symlinks refreshed"
  else
    echo "  - Hermes skills  → not detected (skipped)"
  fi
else
  echo "  (skipped external skills — INIT_SKIP_EXTERNAL_SKILLS=1)"
fi

echo "== local browser QA (chrome-devtools-mcp) =="
zsh tools/install-browser-qa.sh

cat <<'TXT'

For Cursor personas (optional): Settings → Custom Modes → add one per agent,
pasting the body of each .claude/agents/*.md as the instructions.

Next: ./loom wrap claude   or   Use loom-start in Cursor
TXT

if [ "${LOOM_INIT_NO_DASH:-}" != 1 ]; then
  echo "== opening central dashboard =="
  ( zsh "$ROOT/agent-dashboard/serve.sh" >/dev/null 2>&1 & )
  echo "  http://localhost:19000"
fi
