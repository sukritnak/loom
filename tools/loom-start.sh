#!/usr/bin/env zsh
# Bootstrap base folder + control folder — same steps as loom-start / /loom-start skill.
#   zsh tools/loom-start.sh                         full wizard (Steps 1–4)
#   zsh tools/loom-start.sh --new NAME [--base DIR] Step 1 + 2b + 3 + 4 (new-project compat)
#   zsh tools/loom-start.sh --open PATH             Step 3 + 4 only (resume existing control)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

step() { echo; echo "== Step $1 — $2 =="; echo; }

ask() { local p="$1" d="${2:-}" v; read -r "v?$p${d:+ [$d]}: " || true; echo "${v:-$d}"; }

NEW_NAME=""
OPEN_PATH=""
BASE_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --new)  NEW_NAME="${2:-}"; shift 2 ;;
    --open) OPEN_PATH="${2:-}"; shift 2 ;;
    --base) BASE_ARG="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,5p' "$0" | sed 's/^# *//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

printf '%s\n' "$ROOT" > "$HOME/.loop-base" 2>/dev/null || true

ensure_dashboard() {
  step 0 "dashboard (check dash.sh serve)"
  local url port="${STAR_BACKEND_PORT:-19000}"
  if url="$(zsh "$ROOT/tools/dash.sh" up 2>/dev/null)"; then
    echo "✓ Dashboard already running → $url"
    return 0
  fi
  local yn
  yn="$(ask "Open the dashboard to watch agents? [Y/n]" "Y")"
  case "${(L)yn}" in n|no)
    echo "  (skipped — open later: zsh \"$ROOT/tools/dash.sh\" serve)"
    return 0
    ;;
  esac
  ( zsh "$ROOT/tools/dash.sh" serve >/dev/null 2>&1 & )
  sleep 1
  if url="$(zsh "$ROOT/tools/dash.sh" up 2>/dev/null)"; then
    echo "✓ Dashboard → $url"
  else
    echo "✓ Dashboard starting in background → http://localhost:$port"
  fi
}

ensure_dashboard

# --- locale (communication language) ---
source "$ROOT/tools/locale.sh"
if [ -n "$OPEN_PATH" ]; then
  : # lock_project will ensure locale on existing config
else
  LOOM_LOCALE="$(pick_locale "${LOOM_LOCALE:-}")"
  echo "✓ Communication language → $(locale_label "$LOOM_LOCALE")"
fi

lock_project() {
  local dest="$1"
  [ -f "$dest/loop.config.json" ] || { echo "✗ no loop.config.json in $dest" >&2; exit 1; }
  source "$ROOT/tools/locale.sh" 2>/dev/null || true
  if ! read_locale_from_config "$dest" >/dev/null 2>&1; then
    step "0.5" "communication language (locale)"
  fi
  ensure_locale_config "$dest" "${LOOM_LOCALE:-}"
  step 3 "lock target (.active-project — no new folder)"
  printf '%s\n' "$dest" > "$ROOT/.active-project"
  zsh "$ROOT/tools/apply-agent-model.sh" "$dest" 2>/dev/null || true
  echo "✓ Active project → $dest"
  step 4 "hand off to loom-orch"
  cat <<TXT
Next (from Loom chat — no cd required if .active-project is set):
  Use loom-orch at L1: <describe the feature or bug>

Or from the control folder:
  cd "$dest"
  Use loom-orch at L1: <task>

Terminal checks (run from control folder):
  node "$ROOT/tools/cfg.js" resolved
  zsh "$ROOT/tools/verify-paths.sh"
TXT
}

if [ -n "$OPEN_PATH" ]; then
  OPEN_PATH="${OPEN_PATH/#\~/$HOME}"
  lock_project "$OPEN_PATH"
  exit 0
fi

# --- Step 1: base folder ---
step 1 "base folder (job shelf — mkdir if missing)"
SUGGEST="$(zsh "$ROOT/tools/base-dir.sh" suggest)"
DEFAULT="$(zsh "$ROOT/tools/base-dir.sh" "${BASE_ARG:-}")"
if [ -n "$BASE_ARG" ]; then
  BASE="$DEFAULT"
  echo "Using base → $BASE"
else
  echo "Default: $SUGGEST  (outside Loom — not this repo)"
  BASE="$(ask "Where should projects live? [Enter = default]" "$SUGGEST")"
  BASE="$(zsh "$ROOT/tools/base-dir.sh" "$BASE")"
fi

if [ ! -d "$BASE" ]; then
  yn="$(ask "Create base folder $BASE?" "Y")"
  case "${(L)yn}" in n|no) echo "aborted"; exit 1 ;; esac
  mkdir -p "$BASE"
  echo "✓ Created base folder → $BASE"
else
  echo "✓ Base folder → $BASE (already exists — nothing created)"
fi
printf '%s\n' "$BASE" > "$ROOT/.base-dir"

# --- Step 2: control folder ---
step 2 "control folder (open existing or create new)"

if [ -n "$NEW_NAME" ]; then
  CHOICE="2"
  echo "--new $NEW_NAME → create new control folder (Step 2b)"
else
  EXISTING=()
  setopt null_glob localoptions 2>/dev/null || true
  for d in "$BASE"/*/; do
    [ -f "${d}loop.config.json" ] && EXISTING+=("${d%/}")
  done
  if [ ${#EXISTING[@]} -eq 0 ]; then
    echo "No control folders under $BASE yet."
    CHOICE="2"
  else
    echo "Existing control folders:"
    i=1
    for d in "${EXISTING[@]}"; do
      echo "  $i) $(basename "$d") → $d"
      (( i++ ))
    done
    echo
    CHOICE="$(ask "(1) open existing  (2) create new" "1")"
  fi
fi

if [ "$CHOICE" = "1" ]; then
  echo "Step 2a — open existing (no new folder)"
  pick="$(ask "Pick number or full path to control folder" "1")"
  if [[ "$pick" == [0-9]* ]] && [ -n "${EXISTING[${pick:-0}-1]:-}" ]; then
    DEST="${EXISTING[$((pick - 1))]}"
  else
    DEST="${pick/#\~/$HOME}"
  fi
  lock_project "$DEST"
  exit 0
fi

echo "Step 2b — create new control folder + loop.config.json + STATE.md"
NAME="${NEW_NAME:-$(ask "Project name (control folder name)" "")}"
[ -n "$NAME" ] || { echo "project name required"; exit 1; }
DEST="$BASE/$NAME"
if [ -f "$DEST/loop.config.json" ]; then
  echo "✓ $DEST already has loop.config.json — opening instead of creating"
  lock_project "$DEST"
  exit 0
fi
if [ -e "$DEST" ]; then echo "✗ $DEST exists but has no loop.config.json"; exit 1; fi
mkdir -p "$DEST"
cp "$ROOT/STATE.template.md" "$DEST/STATE.md"
echo "✓ Created control folder → $DEST"

( cd "$DEST" && zsh "$ROOT/tools/init-config.sh" )

lock_project "$DEST"
