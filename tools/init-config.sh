#!/usr/bin/env zsh
# Interactive wizard (loom-start Step 2b) — writes loop.config.json in the CURRENT folder.
# Run from a control folder: zsh tools/init-config.sh
set -euo pipefail
B="$(cat ~/.loop-base 2>/dev/null || true)"
[ -n "$B" ] || B="$(cd "$(dirname "$0")/.." && pwd)"

ask() { local p="$1" d="${2:-}" v; read -r "v?$p${d:+ [$d]}: " || true; echo "${v:-$d}"; }

source "$(dirname "$0")/locale.sh"
if [ -z "${LOOM_LOCALE:-}" ]; then
  LOOM_LOCALE="$(pick_locale)"
fi

pick_model() {
  local platform="$1" default_n="${2:-1}"
  echo
  echo "Models for $platform:"
  node "$B/tools/resolve-agent-model.js" list "$platform" | node -e "
const lines = require('fs').readFileSync(0,'utf8');
const opts = JSON.parse(lines);
opts.forEach((o,i) => console.log('  ' + (i+1) + ') ' + o.label + (o.default ? ' (default)' : '')));
process.stdout.write('DEFAULT_ID=' + (opts.find(o=>o.default)||opts[0]).id + '\n');
" > /tmp/loom-model-pick.$$
  local default_id
  default_id="$(grep '^DEFAULT_ID=' /tmp/loom-model-pick.$$ | cut -d= -f2-)"
  sed '/^DEFAULT_ID=/d' /tmp/loom-model-pick.$$
  rm -f /tmp/loom-model-pick.$$
  local pick
  pick="$(ask "  Model choice (number)" "$default_n")"
  node "$B/tools/resolve-agent-model.js" list "$platform" | node -e "
const pick = Number(process.argv[1]);
const opts = JSON.parse(require('fs').readFileSync(0,'utf8'));
const o = opts[pick-1] || opts.find(x=>x.default) || opts[0];
process.stdout.write(o.id);
" "$pick"
}

echo "== loom-start Step 2b — loop.config.json (writes into $(pwd)) =="
[ -n "${LOOM_LOCALE:-}" ] || LOOM_LOCALE="$(pick_locale)"
echo "Communication language → $(locale_label "$LOOM_LOCALE")"
PROJECT=$(ask "Project name" "$(basename "$(pwd)")")
MODE=$(ask "Mode (new = scaffold fresh folders / existing = use what's here)" "new")
AUTO=$(ask "Autonomy (L1 report / L2 assisted / L3 unattended)" "L1")
echo
echo "Agent platform:"
echo "  1) Auto — detect Cursor / Claude Code / Hermes at runtime (default)"
echo "  2) Cursor"
echo "  3) Claude Code"
echo "  4) Hermes"
PLAT_PICK=$(ask "Platform choice (1-4)" "1")
case "$PLAT_PICK" in
  2) AGENT_PLATFORM="cursor" ;;
  3) AGENT_PLATFORM="claude" ;;
  4) AGENT_PLATFORM="hermes" ;;
  *) AGENT_PLATFORM="auto" ;;
esac

CURSOR_MODEL=""; CLAUDE_MODEL=""; HERMES_MODEL=""
if [ "$AGENT_PLATFORM" = "auto" ]; then
  echo
  echo "Auto mode — pick a model for each editor you use (Enter = default):"
  CURSOR_MODEL="$(pick_model cursor 2)"
  CLAUDE_MODEL="$(pick_model claude 2)"
  HERMES_MODEL="$(pick_model hermes 1)"
elif [ "$AGENT_PLATFORM" = "cursor" ]; then
  CURSOR_MODEL="$(pick_model cursor 2)"
elif [ "$AGENT_PLATFORM" = "claude" ]; then
  CLAUDE_MODEL="$(pick_model claude 2)"
else
  HERMES_MODEL="$(pick_model hermes 1)"
fi

echo
echo "Improvement policy — existing code vs team recommendations:"
echo "  conform = match existing style, recommend only"
echo "  guided  = recommend, you pick which to implement (default)"
echo "  auto    = apply all recommendations automatically"
IMPROVEMENT=$(ask "Improvement policy (conform / guided / auto)" "guided")

echo
echo "Each service can sit in its OWN base path:"
echo "  • relative (e.g. 'web', 'apps/api')        → a subfolder under THIS project"
echo "  • absolute (e.g. '/Users/me/work/old-api') → anywhere on disk / a different base"
echo "Add as many FE and BE folders as you want. Press Enter on an empty 'id' to finish."
echo

SVC_LINES=""
while true; do
  echo "-- new service --"
  ID=$(ask "  service id — short name, e.g. web/admin/api (blank = done)" "")
  [ -z "$ID" ] && break
  SIDE=$(ask "  side — fe (frontend/UI) or be (backend/API/data)" "fe")
  if [ "$SIDE" != "fe" ] && [ "$SIDE" != "be" ]; then echo "  side must be fe or be"; continue; fi
  if [ "$SIDE" = "fe" ]; then DEFSTACK="nextjs"; else DEFSTACK="nestjs"; fi
  PATH_=$(ask "  path — relative (under this project) or absolute (its own base)" "$ID")
  STACK=$(ask "  stack hint — fe: nextjs|vite-react|sveltekit|astro / be: nestjs|fastapi|node-express|go" "$DEFSTACK")
  SVC_LINES+="$ID|$SIDE|$PATH_|$STACK"$'\n'
  echo "  added: $ID ($SIDE) -> $PATH_ [$STACK]"
  echo
done

AGENT_PLATFORM="$AGENT_PLATFORM" CURSOR_MODEL="$CURSOR_MODEL" CLAUDE_MODEL="$CLAUDE_MODEL" HERMES_MODEL="$HERMES_MODEL" \
PROJECT="$PROJECT" MODE="$MODE" AUTO="$AUTO" IMPROVEMENT="$IMPROVEMENT" LOOM_LOCALE="${LOOM_LOCALE:-auto}" SVCS="$SVC_LINES" B="$B" node <<'NODE'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const B = process.env.B;
const catalog = JSON.parse(fs.readFileSync(path.join(B, 'tools/agent-models.json'), 'utf8'));
const validate = (platform, model) => {
  const ids = new Set((catalog.models[platform] || []).map(o => o.id));
  if (!ids.has(model)) throw new Error(`invalid ${platform} model: ${model}`);
};
const svcs = (process.env.SVCS || '').split('\n').filter(Boolean).map(l => {
  const [id, side, p, stack] = l.split('|');
  return { id, side, path: p, stack };
});
const platform = process.env.AGENT_PLATFORM || 'auto';
const agent_models = {
  cursor: process.env.CURSOR_MODEL || catalog.defaults.cursor,
  claude: process.env.CLAUDE_MODEL || catalog.defaults.claude,
  hermes: process.env.HERMES_MODEL || catalog.defaults.hermes,
};
for (const [p, m] of Object.entries(agent_models)) validate(p, m);
const cfg = {
  project: process.env.PROJECT,
  mode: process.env.MODE,
  services: svcs,
  autonomy: process.env.AUTO,
  locale: process.env.LOOM_LOCALE || 'auto',
  agent_platform: platform,
  agent_models,
  improvement_policy: process.env.IMPROVEMENT || 'guided',
};
if (platform !== 'auto') {
  cfg.agent_model = agent_models[platform];
}
fs.writeFileSync('loop.config.json', JSON.stringify(cfg, null, 2) + '\n');
console.log('\nWrote loop.config.json with ' + svcs.length + ' service(s).');
console.log('Platform:', platform);
console.log('Models:', JSON.stringify(agent_models));
NODE

echo "Next: node \"$B/tools/cfg.js\" resolved   (review)   then   zsh \"$B/tools/scaffold-all.sh\"   (scaffold, if mode=new)"
