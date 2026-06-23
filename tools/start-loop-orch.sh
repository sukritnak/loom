#!/usr/bin/env bash
# Pick (or create) the DESTINATION project, remember it in .active-project, and print the
# exact loop-orch command that targets THAT project's loop.config.json. This is the safety
# pointer: it guarantees the loop edits the right project (never this blueprint).
#
#   start-loop-orch.sh                 # use the active project (or pick/create if none)
#   start-loop-orch.sh <name>          # switch to base_dir/<name> (create it if missing)
#   start-loop-orch.sh --new <name>    # always create base_dir/<name>
#   start-loop-orch.sh --list          # list known projects + the active one
#   start-loop-orch.sh --where         # print only the active project path
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POINTER="$ROOT/.active-project"
BASE="$(bash "$ROOT/tools/base-dir.sh")"

valid() { [ -n "${1:-}" ] && [ -f "$1/loop.config.json" ]; }
set_pointer() { printf '%s\n' "$1" > "$POINTER"; }

list() {
  echo "base: $BASE"
  local active=""; [ -f "$POINTER" ] && active="$(cat "$POINTER")"
  shopt -s nullglob
  local found=0
  for d in "$BASE"/*/; do
    d="${d%/}"; valid "$d" || continue; found=1
    [ "$d" = "$active" ] && echo "  * $(basename "$d")  (active)" || echo "    $(basename "$d")"
  done
  [ "$found" = 1 ] || echo "  (no projects yet — create with: make new-project NAME=...)"
}

create_new() { # create_new <name>
  ( BASE_DIR="$BASE" bash "$ROOT/tools/new-project.sh" "$1" )
}

show() { # show <dir>
  local d="$1" auto
  auto="$(cd "$d" && node tools/cfg.js get autonomy)"; auto="${auto:-L1}"
  echo
  echo "Active project → $d"
  echo "config         → $d/loop.config.json"
  echo "  project=$(cd "$d" && node tools/cfg.js get project)  mode=$(cd "$d" && node tools/cfg.js get mode)  autonomy=$auto"
  echo "  services: $(cd "$d" && node tools/cfg.js ids)"
  cat <<TXT

Run the loop FROM that folder (so loop-orch reads ITS loop.config.json):
  cd "$d"
  # Claude Code / Cursor: open this folder, then:
  Use loop-orch at $auto: <describe the feature or bug>
  # Hermes (run inside the folder):
  /loop-orch  run at $auto: <describe the feature or bug>
TXT
}

case "${1:-}" in
  --list)  list; exit 0 ;;
  --where) [ -f "$POINTER" ] && cat "$POINTER" || { echo "no active project"; exit 1; }; exit 0 ;;
  --new)   NAME="${2:?usage: --new <name>}"; create_new "$NAME"; DIR="$BASE/$NAME" ;;
  "")
    if [ -f "$POINTER" ] && valid "$(cat "$POINTER")"; then
      DIR="$(cat "$POINTER")"
    else
      echo "No active project. Choose one or create new:"; list; echo
      read -r -p "Project name (existing or new): " NAME
      [ -n "$NAME" ] || { echo "name required"; exit 1; }
      DIR="$BASE/$NAME"
      valid "$DIR" || create_new "$NAME"
    fi ;;
  *)       NAME="$1"; DIR="$BASE/$NAME"; valid "$DIR" || create_new "$NAME" ;;
esac

valid "$DIR" || { echo "✗ $DIR has no loop.config.json"; exit 1; }
set_pointer "$DIR"
show "$DIR"
