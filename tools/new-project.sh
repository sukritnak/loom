#!/usr/bin/env zsh
# Bootstrap a real project from this blueprint. The project (with its own
# loop.config.json) is created at the DESTINATION, not inside this blueprint.
#   Usage: zsh tools/new-project.sh [project-name] [base-dir]
#   Base dir precedence: [base-dir arg] > $BASE_DIR > .base-dir file > ~/Documents/coding/agent-build
#   Set your own default once by writing the path into the blueprint's .base-dir file.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

BASE="$(zsh "$ROOT/tools/base-dir.sh" "${2:-}")"
NAME="${1:-}"
[ -n "$NAME" ] || read -r 'NAME?Project name: '
[ -n "$NAME" ] || { echo "project name required"; exit 1; }

DEST="$BASE/$NAME"
if [ -e "$DEST" ]; then echo "✗ $DEST already exists"; exit 1; fi
mkdir -p "$DEST"

# The control folder holds ONLY the project's own state: loop.config.json + STATE.md.
# tools/, LOOP.md, and agent-dashboard are NOT copied — they live ONLY in the blueprint (Base)
# and are shared by every project/session. Tools read this folder's loop.config.json from cwd.
cp "$ROOT/STATE.template.md" "$DEST/STATE.md"

# Register the blueprint path so any project can locate the central tools + dashboard.
printf '%s\n' "$ROOT" > "$HOME/.loop-base" 2>/dev/null || true

echo "Created $DEST"
echo "Now configure its services:"
echo
( cd "$DEST" && zsh "$ROOT/tools/init-config.sh" )

cat <<TXT

Done. Your project lives at:
  $DEST

The loop tools live in the blueprint (Base): $ROOT/tools
Next (run from the project folder):
  cd "$DEST"
  node "$ROOT/tools/cfg.js" resolved      # review services
  zsh "$ROOT/tools/scaffold-all.sh"      # scaffold (mode=new)
  zsh "$ROOT/tools/dash.sh" serve        # open the central dashboard
Then run the loop (Claude Code / Cursor / Hermes):
  Use loop-orch at L1: <describe the feature or bug>
TXT
