#!/usr/bin/env bash
# Guided entry point. Run: make loop-start
# Walks you through, in order:
#   1) deploy the agent team (you choose)
#   2) pick the base folder for projects (default or your own path; create if missing)
#   3) create a NEW project or open an EXISTING one (with a list to pick from)
#   4) set the .active-project pointer and print the exact loop-orch command
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

confirm() { # confirm "question" [default y|n]
  local q="$1" d="${2:-y}" a hint
  [ "$d" = y ] && hint="Y/n" || hint="y/N"
  read -r -p "$q [$hint] " a || true
  a="${a:-$d}"; case "$a" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

list_projects() { # list_projects <base> -> abs paths that contain loop.config.json
  local base="$1" d
  shopt -s nullglob
  for d in "$base"/*/; do d="${d%/}"; [ -f "$d/loop.config.json" ] && printf '%s\n' "$d"; done
}

echo "================ AI Agent Office — loop-start ================"

# 1) DEPLOY ---------------------------------------------------------
deployed=no
{ [ -f "$HOME/.claude/agents/tech-loop-orchestrator.md" ] || [ -d "$HOME/.hermes/skills/loop-orch" ]; } && deployed=yes
echo
echo "[1/4] Deploy the agent team (Claude Code + Hermes)"
echo "      currently deployed: $deployed"
if confirm "      Deploy / refresh now?" "$([ "$deployed" = yes ] && echo n || echo y)"; then
  bash tools/deploy.sh
fi

# 2) BASE FOLDER ---------------------------------------------------
echo
echo "[2/4] Where should projects live? (absolute path, outside this repo)"
BASE=""
while true; do
  def="$(bash tools/base-dir.sh)"
  read -r -p "      Base folder [$def]: " cand || true
  cand="${cand:-$def}"
  if out="$(bash tools/base-dir.sh "$cand" 2>&1)"; then BASE="$out"; break; fi
  echo "      ✗ $out"
done
printf '%s\n' "$BASE" > "$ROOT/.base-dir"
echo "      base → $BASE  (saved as default)"
if [ ! -d "$BASE" ]; then
  if confirm "      It doesn't exist yet. Create it?" y; then
    mkdir -p "$BASE" && echo "      created $BASE"
  else
    echo "      can't continue without a base folder."; exit 1
  fi
fi

# 3) NEW OR EXISTING ----------------------------------------------
echo
echo "[3/4] Choose a project"
PROJS=()
while IFS= read -r d; do [ -n "$d" ] && PROJS+=("$d"); done < <(list_projects "$BASE")
if [ "${#PROJS[@]}" -gt 0 ]; then
  echo "      existing in $BASE:"
  i=1; for p in "${PROJS[@]}"; do printf "        %d) %s\n" "$i" "$(basename "$p")"; i=$((i+1)); done
else
  echo "      (no projects here yet)"
fi
echo "        n) create a NEW project"
echo "        p) open an EXISTING project by full path"
read -r -p "      Choose (number / n / p) [n]: " choice || true
choice="${choice:-n}"

DIR=""
case "$choice" in
  n|N)
    read -r -p "      New project name: " NAME || true
    [ -n "$NAME" ] || { echo "      name required"; exit 1; }
    DIR="$BASE/$NAME"
    if [ -f "$DIR/loop.config.json" ]; then
      echo "      '$NAME' already exists — opening it."
    elif [ -e "$DIR" ]; then
      echo "      '$DIR' exists but has no loop.config.json — running setup there."
      ( cd "$DIR" && bash "$ROOT/tools/init-config.sh" )
    else
      bash tools/new-project.sh "$NAME" "$BASE"
    fi
    ;;
  p|P)
    while true; do
      read -r -p "      Full path to existing project: " P || true
      P="${P%/}"
      case "$P" in /*) ;; *) echo "      ✗ must be an absolute path"; continue ;; esac
      if [ "$P" = "$PWD" ] || [ "$P" = "$ROOT" ]; then echo "      ✗ not the current / blueprint folder"; continue; fi
      [ -f "$P/loop.config.json" ] || { echo "      ✗ no loop.config.json in $P"; continue; }
      DIR="$P"; break
    done
    ;;
  *[!0-9]*|"")
    echo "      invalid choice"; exit 1 ;;
  *)
    idx=$((choice-1))
    [ "$idx" -ge 0 ] && [ "$idx" -lt "${#PROJS[@]}" ] || { echo "      no such project"; exit 1; }
    DIR="${PROJS[$idx]}" ;;
esac

[ -f "$DIR/loop.config.json" ] || { echo "✗ $DIR has no loop.config.json"; exit 1; }

# 4) POINTER + COMMAND --------------------------------------------
printf '%s\n' "$DIR" > "$ROOT/.active-project"
echo
echo "[4/4] Active project set."
exec bash tools/start-loop-orch.sh
