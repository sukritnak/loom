#!/usr/bin/env zsh
# Install recommended external skills → ~/.agents/skills/ (idempotent).
# Called by deploy.sh on first setup; safe to re-run.
# Skip: DEPLOY_SKIP_EXTERNAL_SKILLS=1 zsh tools/deploy.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="${HOME}/.agents/skills"

EXTERNAL=(solid postgres-best-practices docker-containerization perf-lighthouse \
  threejs-animation ponytail ponytail-review ponytail-audit)

have() { [ -f "$SKILLS_DIR/$1/SKILL.md" ] || [ -d "$SKILLS_DIR/$1" ]; }

need=()
for s in "${EXTERNAL[@]}"; do have "$s" || need+=("$s"); done

if [ ${#need[@]} -eq 0 ]; then
  echo "  ✓ external skills already present (${EXTERNAL[*]})"
else
  if command -v npx >/dev/null 2>&1; then
    echo "== installing external skills: ${need[*]} =="
    npx --yes skills add "${need[@]}"
  else
    echo "  ! npx not found — install Node.js, then: zsh tools/install-external-skills.sh" >&2
    exit 1
  fi
fi

if have qa; then
  echo "  ✓ qa-browser skill already present"
else
  zsh "$ROOT/tools/install-browser-use-qa.sh"
fi

echo "Done → $SKILLS_DIR"
