#!/usr/bin/env zsh
# purge-legacy-agents.sh — remove pre-loom-* agent installs (v1.0.2 and earlier), then reinstall.
#
# Use when you installed Loom before the agent rename (loop-start, pm, be, …) and still see
# old names in Claude Code, Hermes, or Cursor Settings → Agents → Subagents.
#
# Safe to re-run. Does NOT touch loop.config.json, STATE.md, or project code.
#
# Usage (from this blueprint repo, after git pull):
#   zsh tools/purge-legacy-agents.sh
#   zsh tools/purge-legacy-agents.sh --dry-run   # print only, no deletes
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DRY=0
[[ "${1:-}" == --dry-run ]] && DRY=1

# Pre-rename agent IDs (frontmatter `name:` and Hermes skill folder names)
OLD_IDS=(loop-start loop-orch pm design fe fe-anim be be-sr qa)
# Pre-rename agent filenames under ~/.claude/agents and ~/.cursor/agents
OLD_AGENT_FILES=(
  loop-start.md tech-loop-orchestrator.md designer-agent.md
  frontend-animation-agent.md backend-senior-agent.md
)
# Pre-rename Hermes skill dirs (install-hermes-skills wipes all anyway; listed for dry-run clarity)
OLD_HERMES=(loop-start loop-orch pm design fe fe-anim be be-sr qa LOOP)

rm_path() {
  local p="$1"
  [[ -e "$p" ]] || return 0
  if (( DRY )); then
    echo "  would remove: $p"
  else
    rm -rf "$p"
    echo "  removed: $p"
  fi
}

purge_agent_dir() {
  local dir="$1" label="$2"
  [[ -d "$dir" ]] || { echo "  ($label — not present, skip)"; return 0; }
  echo "== $label: $dir =="
  setopt null_glob 2>/dev/null || true
  for id in "${OLD_IDS[@]}"; do rm_path "$dir/$id.md"; done
  for f in "${OLD_AGENT_FILES[@]}"; do rm_path "$dir/$f"; done
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    name="$(awk '/^---$/{n++; next} n==1 && /^name:/{print $2; exit}' "$f" 2>/dev/null || true)"
    for id in "${OLD_IDS[@]}"; do
      [[ "$name" == "$id" ]] && rm_path "$f" && break
    done
  done
  unsetopt null_glob 2>/dev/null || true
}

echo "== purge legacy Loom agents (pre loom-* namespace) =="
(( DRY )) && echo "(dry-run — no files changed)"
echo ""

purge_agent_dir "$HOME/.claude/agents" "Claude Code"
purge_agent_dir "$HOME/.cursor/agents" "Cursor user subagents"
purge_agent_dir "$ROOT/.cursor/agents" "Cursor project subagents"

if [[ -d "$HOME/.hermes/skills" ]]; then
  echo "== Hermes: ~/.hermes/skills =="
  for s in "${OLD_HERMES[@]}"; do rm_path "$HOME/.hermes/skills/$s"; done
  # feanim / besr aliases from older dashboard slot ids
  rm_path "$HOME/.hermes/skills/feanim"
  rm_path "$HOME/.hermes/skills/besr"
else
  echo "  (Hermes skills dir not present, skip)"
fi

if (( DRY )); then
  echo ""
  echo "Dry-run done. Re-run without --dry-run, then:"
  echo "  zsh tools/sync-agents.sh"
  exit 0
fi

echo ""
echo "== reinstall loom-* agents =="
zsh "$ROOT/tools/sync-agents.sh"

echo ""
cat <<'TXT'
Done.

Verify:
  Claude Code  → ls ~/.claude/agents/   (9 files, name: loom-* in frontmatter)
  Hermes       → ls ~/.hermes/skills/   (loom-start … loom-qa, LOOM)
  Cursor       → Cmd+Shift+P → Developer: Reload Window
                 Settings → Agents → Subagents → loom-start, loom-orch, loom-pm, …

If Cursor still shows old names: delete them manually in Subagents (⋯ → Delete), reload again.
TXT
