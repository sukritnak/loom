#!/usr/bin/env zsh
# apply-agent-model.sh — sync loop.config.json agent_models → platform agent copies.
# Run from control folder (or pass control folder as $1).
set -euo pipefail
B="$(cat ~/.loop-base 2>/dev/null || true)"
[ -n "$B" ] || { echo "✗ ~/.loop-base missing — run init.sh first" >&2; exit 1; }

DEST="${1:-$(pwd)}"
CFG="$DEST/loop.config.json"
[ -f "$CFG" ] || { echo "✗ no loop.config.json in $DEST" >&2; exit 1; }

patch_dir() {
  local dir="$1" model="$2"
  [ -d "$dir" ] || return 0
  local n=0
  setopt null_glob 2>/dev/null || true
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    if grep -q '^model:' "$f"; then
      sed -i '' "s/^model:.*/model: $model/" "$f"
    else
      awk -v m="$model" '
        NR==1 && $0=="---" { print; infm=1; next }
        infm && /^description:/ { print; print "model: " m; next }
        { print }
      ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    fi
    (( n++ )) || true
  done
  unsetopt null_glob 2>/dev/null || true
  [ "$n" -gt 0 ] && echo "  ✓ $dir ($n agents → $model)"
}

eval "$(B="$B" DEST="$DEST" node -e "
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const B = process.env.B;
const DEST = process.env.DEST;
const r = spawnSync('node', [path.join(B, 'tools/resolve-agent-model.js')], {
  cwd: DEST, env: { ...process.env, LOOM_BASE: B }, encoding: 'utf8',
});
if (r.status !== 0) { console.error(r.stderr || r.stdout); process.exit(1); }
const info = JSON.parse(r.stdout);
const m = info.agent_models || {};
console.log('CURSOR_MODEL=' + JSON.stringify(m.cursor || 'composer-2.5'));
console.log('CLAUDE_MODEL=' + JSON.stringify(m.claude || 'sonnet'));
console.log('HERMES_MODEL=' + JSON.stringify(m.hermes || 'inherit'));
console.log('PLATFORM=' + JSON.stringify(info.agent_platform || 'auto'));
fs.mkdirSync(path.join(DEST, '.loom'), { recursive: true });
fs.writeFileSync(path.join(DEST, '.loom', 'agent-model.json'), JSON.stringify(info, null, 2) + '\n');
")"

echo "== apply agent models (platform: $PLATFORM) =="
patch_dir "$HOME/.cursor/agents" "$CURSOR_MODEL"
patch_dir "$HOME/.claude/agents" "$CLAUDE_MODEL"
printf '%s\n' "$HERMES_MODEL" > "$DEST/.loom/hermes-model"
echo "  ✓ $DEST/.loom/agent-model.json + hermes-model → $HERMES_MODEL"

if [[ "$HERMES_MODEL" != "inherit" ]] && command -v hermes >/dev/null 2>&1; then
  echo "  (Hermes) start with: hermes -m \"$HERMES_MODEL\""
fi
echo "Done. Reload Cursor / restart Claude Code if agents were already loaded."
