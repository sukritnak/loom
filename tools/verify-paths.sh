#!/usr/bin/env bash
# Verify the FE/BE folders in loop.config.json before any work.
#  - mode "existing": every service path MUST already exist + be readable; missing ones are flagged
#    and you'll be told to grant access (connect the folder in Cowork, or use a path inside an
#    allowed root in Claude Code CLI).
#  - mode "new": folders are created under THIS project root (where loop.config.json lives).
# Service paths are relative to this folder (cwd) or absolute.
# Exit code: 0 = all good, 1 = something needs your attention.
set -uo pipefail
CFG="node tools/cfg.js"
MODE=$($CFG get mode)
PROJECT=$($CFG get project)
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
  done < <($CFG resolved)

  if [ "$problems" -gt 0 ]; then
    echo
    echo "⚠ $problems folder(s) not accessible. To fix:"
    echo "  • Cowork: connect/grant access to the folder above, then re-run."
    echo "  • Claude Code CLI: run from a parent dir that contains it, or use an absolute path inside an allowed root."
    echo "  • Or fix the path in loop.config.json (run: make setup)."
  fi
else
  # mode new — folders are created under this project root
  echo "New folders will be created under: $(pwd)"
  while IFS=$'\t' read -r id side abspath stack; do
    [ -z "$id" ] && continue
    if [ -d "$abspath" ]; then echo "  exists   $id → $abspath (will reuse)"; else echo "  to-make  $id ($side) → $abspath"; fi
  done < <($CFG resolved)
  [ "$problems" -eq 0 ] && echo && echo "Ready. Run: make init   (scaffold all)  or  make scaffold SVC=<id>"
fi

exit $([ "$problems" -eq 0 ] && echo 0 || echo 1)
