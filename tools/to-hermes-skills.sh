#!/usr/bin/env zsh
# Convert Claude Code subagent files (*-agent.md, tech-loop-orchestrator.md) into
# SKILL.md skills for Hermes Agent (or any agentskills.io-compatible agent).
# It keeps `name` + `description`, drops `tools:`/`model:`, and writes
# hermes-skills/<name>/SKILL.md. Run from the control-repo root.
set -euo pipefail

SRC_DIR="${1:-.claude/agents}"        # where the agent .md files live
OUT_DIR="${2:-hermes-skills}"         # output skills dir (copy to ~/.hermes/skills/)

setopt null_glob 2>/dev/null || true
files=("$SRC_DIR"/*.md)
[ ${#files[@]} -gt 0 ] || { echo "no .md files in $SRC_DIR"; exit 1; }

for f in "${files[@]}"; do
  # pull the skill name from frontmatter (fallback: filename)
  name=$(awk -F': *' '/^name:/{print $2; exit}' "$f")
  [ -n "$name" ] || name=$(basename "$f" .md)
  dest="$OUT_DIR/$name"
  mkdir -p "$dest"
  # rewrite: keep frontmatter but strip tools:/model: lines
  awk '
    NR==1 && $0=="---" {infm=1; print; next}
    infm && $0=="---" {infm=0; print; next}
    infm && /^(tools|model):/ {next}
    {print}
  ' "$f" > "$dest/SKILL.md"
  echo "  + $dest/SKILL.md"
done

# Also expose the loop spec as a skill (LOOP.md has no frontmatter, so add one).
if [ -f LOOP.md ]; then
  mkdir -p "$OUT_DIR/LOOP"
  { printf -- '---\nname: loop\ndescription: Loop-engineering spec for this team — primitives (STATE.md, loop.config.json), L1/L2/L3 phases, safety denylist, iteration anatomy. Use when the user asks how the loop works, which autonomy level to use, or what the orchestrator should do between runs.\n---\n'; cat LOOP.md; } > "$OUT_DIR/LOOP/SKILL.md"
  echo "  + $OUT_DIR/LOOP/SKILL.md"
fi

echo "Done → $OUT_DIR"
echo "Install into Hermes:  zsh tools/install-hermes-skills.sh"
