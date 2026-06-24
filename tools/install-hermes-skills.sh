#!/usr/bin/env zsh
# Install only the skills this team needs into ~/.hermes/skills/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/hermes-skills"
DEST="${1:-$HOME/.hermes/skills}"

# team roles + loop spec only (human guides stay in repo — not Hermes skills)
NEEDED=(loop-start loop-orch pm design fe fe-anim be be-sr qa LOOP)

EXTERNAL=(solid postgres-best-practices docker-containerization perf-lighthouse threejs-animation ponytail ponytail-review ponytail-audit)

mkdir -p "$DEST"
find "$DEST" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

for s in "${NEEDED[@]}"; do
  [ -d "$SRC/$s" ] || { echo "missing hermes-skills/$s — run: zsh tools/to-hermes-skills.sh"; exit 1; }
  cp -R "$SRC/$s" "$DEST/$s"
  echo "  + $s"
done

for s in "${EXTERNAL[@]}"; do
  if [ -d "$HOME/.agents/skills/$s" ]; then
    ln -sf "../../.agents/skills/$s" "$DEST/$s"
    echo "  ~ $s (symlink)"
  fi
done
if [ -d "$HOME/.agents/skills/qa" ]; then
  ln -sf "../../.agents/skills/qa" "$DEST/qa-browser"
  echo "  ~ qa-browser (symlink)"
fi

echo "Done → $DEST (${#NEEDED[@]} skills + external symlinks)"
