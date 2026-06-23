#!/usr/bin/env bash
# Bootstrap a real project from this blueprint. The project (with its own
# loop.config.json) is created at the DESTINATION, not inside this blueprint.
#   Usage: bash tools/new-project.sh [project-name] [base-dir]
#   Base dir precedence: [base-dir arg] > $BASE_DIR > .base-dir file > ~/Documents/coding/agent-build
#   Set your own default once with:  make set-base DIR=/path
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

BASE="$(bash "$ROOT/tools/base-dir.sh" "${2:-}")"
NAME="${1:-}"
[ -n "$NAME" ] || read -r -p "Project name: " NAME
[ -n "$NAME" ] || { echo "project name required"; exit 1; }

DEST="$BASE/$NAME"
if [ -e "$DEST" ]; then echo "✗ $DEST already exists"; exit 1; fi
mkdir -p "$DEST"

# copy the loop infra (NOT the agent definitions — those live at platform level via deploy.sh)
cp "$ROOT/Makefile" "$DEST/"
cp "$ROOT/LOOP.md" "$DEST/"
cp "$ROOT/loop.config.example.json" "$DEST/"
cp "$ROOT/STATE.template.md" "$DEST/STATE.md"
cp -R "$ROOT/tools" "$DEST/tools"
cp -R "$ROOT/agent-dashboard" "$DEST/agent-dashboard"

echo "Created $DEST"
echo "Now configure its services:"
echo
( cd "$DEST" && bash tools/init-config.sh )

cat <<TXT

Done. Your project lives at:
  $DEST

Next:
  cd "$DEST"
  make config        # review services
  make init          # scaffold (mode=new)
  make dashboard     # live status board
Then run the loop (Claude Code / Cursor / Hermes):
  Use loop-orch at L1: <describe the feature or bug>
TXT
