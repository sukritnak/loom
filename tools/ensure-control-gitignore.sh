#!/usr/bin/env zsh
# Control folder — keep Loom secrets out of git (idempotent). Run from control cwd.
set -euo pipefail
MARKER="# loom-control-secrets"
FILE=".gitignore"
BLOCK="${MARKER}
.loom/
browser-use.env
browser-use.env.*
"

if [ -f "$FILE" ] && grep -q "$MARKER" "$FILE" 2>/dev/null; then
  exit 0
fi
if [ -f "$FILE" ]; then
  printf '\n%s' "$BLOCK" >>"$FILE"
else
  printf '%s' "$BLOCK" >"$FILE"
fi
