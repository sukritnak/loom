#!/usr/bin/env zsh
# Resolve the base folder where NEW projects are created. Single source of truth.
# Precedence:  $1 (explicit arg) > $BASE_DIR env > .base-dir file > built-in default
# Set your own default by writing the path into the .base-dir file (loop-start does this for you).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT="$HOME/Documents/coding/agent-build"

b="${1:-${BASE_DIR:-}}"
[ -n "$b" ] || { [ -f "$ROOT/.base-dir" ] && b="$(head -n1 "$ROOT/.base-dir")"; }
[ -n "$b" ] || b="$DEFAULT"
b="${b/#\~/$HOME}"
b="${b%/}"

# Guard: base dir must be an absolute path OUTSIDE the blueprint — never the current/blueprint dir.
case "$b" in
  ""|"."|"./") echo "base dir cannot be the current directory" >&2; exit 1 ;;
  /*) ;;
  *) echo "base dir must be an absolute path (got: '$b')" >&2; exit 1 ;;
esac
if [ "$b" = "$PWD" ] || [ "$b" = "$ROOT" ] || case "$b/" in "$ROOT/"*) true ;; *) false ;; esac; then
  echo "base dir must be OUTSIDE the blueprint repo ($ROOT) — pick another folder" >&2
  exit 1
fi

printf '%s\n' "$b"
