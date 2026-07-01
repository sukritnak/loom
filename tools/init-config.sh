#!/usr/bin/env zsh
# Interactive wizard (loom-start Step 2b) — writes loop.config.json in the CURRENT folder.
set -euo pipefail
B="$(cat ~/.loop-base 2>/dev/null || true)"
[ -n "$B" ] || B="$(cd "$(dirname "$0")/.." && pwd)"

source "$(dirname "$0")/wizard-menu.sh"
source "$(dirname "$0")/locale.sh"

ask_text() { local p="$1" d="${2:-}" v; read -r "v?$p${d:+ [$d]}: " || true; echo "${v:-$d}"; }

if [ -z "${LOOM_LOCALE:-}" ]; then
  LOOM_LOCALE="$(pick_locale)"
fi

pick_model() {
  local platform="$1" default_n="${2:-1}"
  echo
  echo "Models for $platform:"
  local -a labels=()
  local line default_n_actual=1
  while IFS= read -r line; do
    [[ "$line" == DEFAULT_N=* ]] && { default_n_actual="${line#DEFAULT_N=}"; continue; }
    [[ -n "$line" ]] && labels+=("$line")
  done < <(node "$B/tools/resolve-agent-model.js" list "$platform" | node -e "
const opts = JSON.parse(require('fs').readFileSync(0,'utf8'));
let def = 1;
opts.forEach((o,i) => {
  const n = i + 1;
  if (o.default) def = n;
  console.log(o.label + (o.default ? ' (default)' : ''));
});
console.log('DEFAULT_N=' + def);
")
  local pick_label
  pick_label="$(menu_pick "  Pick model" "${default_n:-$default_n_actual}" "${labels[@]}")"
  pick_label="${pick_label% (default)}"
  node "$B/tools/resolve-agent-model.js" list "$platform" | node -e "
const label = process.argv[1];
const opts = JSON.parse(require('fs').readFileSync(0,'utf8'));
const o = opts.find(x => x.label === label) || opts.find(x => x.default) || opts[0];
process.stdout.write(o.id);
" "$pick_label"
}

echo "== loom-start Step 2b — loop.config.json (writes into $(pwd)) =="
echo "Communication language → $(locale_label "$LOOM_LOCALE")"

DEFAULT_NAME="$(basename "$(pwd)")"
NAME_PICK="$(menu_pick "Project name" 1 "$DEFAULT_NAME (use folder name)" "Type a different name…")"
if [[ "$NAME_PICK" == "Type a different name…" ]]; then
  PROJECT="$(ask_text "  Project name" "$DEFAULT_NAME")"
else
  PROJECT="$DEFAULT_NAME"
fi

case "$(menu_pick "Project mode" 1 \
  "new — scaffold fresh folders (recommended)" \
  "existing — use code folders already on disk")" in
  existing*) MODE="existing" ;;
  *) MODE="new" ;;
esac

case "$(menu_pick "Autonomy level" 1 \
  "L1 — report only (recommended)" \
  "L2 — assisted (makers write, you merge)" \
  "L3 — unattended")" in
  L2*) AUTO="L2" ;;
  L3*) AUTO="L3" ;;
  *) AUTO="L1" ;;
esac

case "$(menu_pick "Agent platform" 1 \
  "Auto — detect Cursor / Claude Code / Hermes (recommended)" \
  "Cursor" \
  "Claude Code" \
  "Hermes")" in
  Cursor) AGENT_PLATFORM="cursor" ;;
  "Claude Code") AGENT_PLATFORM="claude" ;;
  Hermes) AGENT_PLATFORM="hermes" ;;
  *) AGENT_PLATFORM="auto" ;;
esac

CURSOR_MODEL=""; CLAUDE_MODEL=""; HERMES_MODEL=""
if [ "$AGENT_PLATFORM" = "auto" ]; then
  echo
  echo "Auto mode — pick a model for each editor:"
  CURSOR_MODEL="$(pick_model cursor)"
  CLAUDE_MODEL="$(pick_model claude)"
  HERMES_MODEL="$(pick_model hermes)"
elif [ "$AGENT_PLATFORM" = "cursor" ]; then
  CURSOR_MODEL="$(pick_model cursor)"
elif [ "$AGENT_PLATFORM" = "claude" ]; then
  CLAUDE_MODEL="$(pick_model claude)"
else
  HERMES_MODEL="$(pick_model hermes)"
fi

case "$(menu_pick "Improvement policy" 2 \
  "conform — match existing style, recommend only" \
  "guided — recommend, you pick (recommended)" \
  "auto — apply all recommendations")" in
  conform*) IMPROVEMENT="conform" ;;
  auto*) IMPROVEMENT="auto" ;;
  *) IMPROVEMENT="guided" ;;
esac

SVC_LINES=""
case "$(menu_pick "Services setup" 1 \
  "web + api — Next.js + NestJS (recommended)" \
  "Frontend only — Next.js" \
  "Backend only — NestJS" \
  "Custom — add services one by one")" in
  "web + api"*)
    SVC_LINES=$'web|fe|web|nextjs\napi|be|api|nestjs\n' ;;
  "Frontend only"*)
    SVC_LINES=$'web|fe|web|nextjs\n' ;;
  "Backend only"*)
    SVC_LINES=$'api|be|api|nestjs\n' ;;
  *)
    echo
    echo "Custom services — pick options; type only when choosing custom path."
    while true; do
      echo "-- new service --"
      ID="$(ask_text "  service id (blank = done)" "")"
      [ -z "$ID" ] && break
      case "$(menu_pick "  Side" 1 "fe — frontend/UI" "be — backend/API")" in
        be*) SIDE="be"; DEFSTACK="nestjs" ;;
        *) SIDE="fe"; DEFSTACK="nextjs" ;;
      esac
      case "$(menu_pick "  Path" 1 "Same as id ($ID)" "Custom path…")" in
        "Custom path"*) PATH_="$(ask_text "  path" "$ID")" ;;
        *) PATH_="$ID" ;;
      esac
      if [ "$SIDE" = "fe" ]; then
        case "$(menu_pick "  Stack" 1 "nextjs (recommended)" "vite-react" "sveltekit" "astro" "none")" in
          vite*) STACK="vite-react" ;;
          svelte*) STACK="sveltekit" ;;
          astro*) STACK="astro" ;;
          none*) STACK="" ;;
          *) STACK="nextjs" ;;
        esac
      else
        case "$(menu_pick "  Stack" 1 "nestjs (recommended)" "fastapi" "node-express" "go" "none")" in
          fastapi*) STACK="fastapi" ;;
          node*) STACK="node-express" ;;
          go*) STACK="go" ;;
          none*) STACK="" ;;
          *) STACK="nestjs" ;;
        esac
      fi
      SVC_LINES+="$ID|$SIDE|$PATH_|$STACK"$'\n'
      echo "  added: $ID ($SIDE) -> $PATH_ [$STACK]"
      menu_yesno "Add another service?" 0 || break
    done
    ;;
esac

AGENT_PLATFORM="$AGENT_PLATFORM" CURSOR_MODEL="$CURSOR_MODEL" CLAUDE_MODEL="$CLAUDE_MODEL" HERMES_MODEL="$HERMES_MODEL" \
PROJECT="$PROJECT" MODE="$MODE" AUTO="$AUTO" IMPROVEMENT="$IMPROVEMENT" LOOM_LOCALE="${LOOM_LOCALE:-auto}" SVCS="$SVC_LINES" B="$B" node <<'NODE'
const fs = require('fs');
const path = require('path');
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
