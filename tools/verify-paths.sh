#!/usr/bin/env zsh
# Verify the FE/BE folders in loop.config.json before any work.
#  - mode "existing": every service path MUST already exist + be readable; missing ones are flagged
#    and you'll be told to grant access (connect the folder in Cowork, or use a path inside an
#    allowed root in Claude Code CLI).
#  - mode "new": folders are created under THIS project root (where loop.config.json lives).
# Service paths are relative to this folder (cwd) or absolute.
# Run from the PROJECT (control) folder; tools live in the Base blueprint and find
# their siblings next to themselves, while loop.config.json is read from cwd.
# Exit code: 0 = all good, 1 = something needs your attention.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cfg() { node "$HERE/cfg.js" "$@"; }
MODE=$(cfg get mode)
PROJECT=$(cfg get project)
problems=0

echo "== verify paths =="
echo "project=$PROJECT  mode=$MODE  root=$(pwd)"
echo

if [ "$MODE" = "existing" ]; then
  while IFS=$'\t' read -r id side abspath stack; do
    [ -z "$id" ] && continue
    if [ -d "$abspath" ]; then
      if [ -r "$abspath" ]; then
        echo "  OK       $id ($side) → $abspath"
      else
        echo "  NO-READ  $id ($side) → $abspath   (exists but not readable — grant access)"
        problems=$((problems+1))
      fi
    else
      echo "  MISSING  $id ($side) → $abspath"
      problems=$((problems+1))
    fi
  done < <(cfg resolved)

  if [ "$problems" -gt 0 ]; then
    echo
    echo "⚠ $problems folder(s) not accessible. To fix:"
    echo "  • Cowork: connect/grant access to the folder above, then re-run."
    echo "  • Claude Code CLI: run from a parent dir that contains it, or use an absolute path inside an allowed root."
    echo "  • Or fix the path in loop.config.json (run: zsh \"$HERE/init-config.sh\")."
  fi
else
  # mode new — folders are created under this project root
  echo "New folders will be created under: $(pwd)"
  while IFS=$'\t' read -r id side abspath stack; do
    [ -z "$id" ] && continue
    if [ -d "$abspath" ]; then echo "  exists   $id → $abspath (will reuse)"; else echo "  to-make  $id ($side) → $abspath"; fi
  done < <(cfg resolved)
  [ "$problems" -eq 0 ] && echo && echo "Ready. Run: zsh \"$HERE/scaffold-all.sh\"   (all)  or  zsh \"$HERE/scaffold-all.sh\" <id>"
fi

exit $([ "$problems" -eq 0 ] && echo 0 || echo 1)
