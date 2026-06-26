#!/usr/bin/env zsh
# refresh.sh — idempotent machine sync after clone, pull, or repo move.
# Registers ~/.loop-base, CLI, agents, dashboard hooks, git hooks.
# Usage: zsh tools/refresh.sh [--quiet] [--git-hook]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

QUIET=0
GIT_HOOK=0
for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    --git-hook) GIT_HOOK=1; QUIET=1 ;;
  esac
done

say() { (( QUIET )) || echo "$@"; }

printf '%s\n' "$ROOT" > "$HOME/.loop-base"

say "== Loom refresh =="
zsh tools/install-loom-cli.sh
zsh tools/sync-agents.sh

if [[ "${DEPLOY_SKIP_CC_HOOKS:-}" != 1 ]]; then
  zsh tools/install-dash-hooks.sh
else
  say "  (skipped dashboard hooks — DEPLOY_SKIP_CC_HOOKS=1)"
fi

zsh tools/install-git-hooks.sh

say ""
say "  ✓ blueprint → $ROOT"
say "  ✓ ~/.loop-base · loom CLI · agents · dashboard hooks"
if (( GIT_HOOK )); then
  say "  (refreshed after git pull/checkout)"
else
  say ""
  say "  Next: ./loom wrap claude   or   Use loom-start in Cursor"
  say "  Full install (external skills): zsh tools/deploy.sh"
fi
