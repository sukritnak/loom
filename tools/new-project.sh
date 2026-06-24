#!/usr/bin/env zsh
# Create a new control folder — shortcut for loop-start Step 1 + 2b.
# Prefer the full wizard: zsh tools/loop-start.sh
#   Usage: zsh tools/new-project.sh [project-name] [base-dir]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-}"
BASE="${2:-}"
args=( )
[ -n "$NAME" ] || read -r 'NAME?Project name: '
[ -n "$NAME" ] || { echo "project name required"; exit 1; }
args+=( --new "$NAME" )
[ -n "$BASE" ] && args+=( --base "$BASE" )
exec zsh "$ROOT/tools/loop-start.sh" "${args[@]}"
