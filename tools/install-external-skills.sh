#!/usr/bin/env zsh
# Install recommended external skills → ~/.agents/skills/ (idempotent).
# Called by init.sh on first setup; safe to re-run.
# Skip: INIT_SKIP_EXTERNAL_SKILLS=1 zsh tools/init.sh
#
# ponytail: bare names fail — skills CLI needs owner/repo@skill and -g for global install.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="${HOME}/.agents/skills"
mkdir -p "$SKILLS_DIR"

typeset -A SPECS=(
  solid                    ramziddin/solid-skills@solid
  postgres-best-practices  neondatabase/postgres-skills@postgres-best-practices
  docker-containerization  ailabs-393/ai-labs-claude-skills@docker-containerization
  perf-lighthouse          tech-leads-club/agent-skills@perf-lighthouse  # FE/fe-mo agents only — not BE
  threejs-animation        cloudai-x/threejs-skills@threejs-animation
  ponytail                 dietrichgebert/ponytail@ponytail
  ponytail-review          dietrichgebert/ponytail@ponytail-review
  ponytail-audit           dietrichgebert/ponytail@ponytail-audit
  ui-ux-pro-max            nextlevelbuilder/ui-ux-pro-max-skill@ui-ux-pro-max
)

ORDER=(solid postgres-best-practices docker-containerization perf-lighthouse \
  threejs-animation ponytail ponytail-review ponytail-audit ui-ux-pro-max)

have() { [ -f "$SKILLS_DIR/$1/SKILL.md" ]; }

# Blueprint vendors some skills — copy to global when npx fails or installed project-local only.
vendored() {
  local name=$1 src="$ROOT/.agents/skills/$1"
  [ -f "$src/SKILL.md" ] || return 1
  mkdir -p "$SKILLS_DIR/$name"
  cp -R "$src/." "$SKILLS_DIR/$name/"
  echo "  ✓ $name (from blueprint .agents/skills)"
}

promote_local() {
  local name=$1 src="$ROOT/.agents/skills/$1"
  have "$name" && return 0
  [ -f "$src/SKILL.md" ] || return 1
  vendored "$name"
}

install_one() {
  local name=$1 spec=$2
  if have "$name"; then
    echo "  ✓ $name"
    return 0
  fi
  promote_local "$name" && return 0

  if ! command -v npx >/dev/null 2>&1; then
    vendored "$name" && return 0
    echo "  ✗ $name — npx not found and no vendored copy" >&2
    return 1
  fi

  echo "  + $name ← $spec"
  # -g: ~/.agents/skills (Hermes symlinks expect this). cd $HOME so deploy from blueprint ≠ project install.
  if ( cd "$HOME" && npx --yes skills add "$spec" -g -y ); then
    have "$name" && return 0
  fi
  promote_local "$name" && return 0
  echo "  ✗ $name install failed" >&2
  return 1
}

failed=()
for name in "${ORDER[@]}"; do
  install_one "$name" "${SPECS[$name]}" || failed+=("$name")
done

if have qa; then
  echo "  ✓ qa-browser skill already present"
else
  zsh "$ROOT/tools/install-browser-use-qa.sh"
fi

if have hexagonal-architecture; then
  echo "  ✓ hexagonal-architecture already present"
else
  zsh "$ROOT/tools/install-hexagonal-architecture-skill.sh"
fi

promote_local loom-me || true

if [ ${#failed[@]} -gt 0 ]; then
  echo "  ! failed: ${failed[*]} — retry: zsh tools/install-external-skills.sh" >&2
  exit 1
fi

echo "Done → $SKILLS_DIR"
