#!/usr/bin/env zsh
# Interactive wizard (loom-start Step 2b) — writes loop.config.json in the CURRENT folder.
# Run from a control folder: zsh tools/init-config.sh
set -euo pipefail

ask() { local p="$1" d="${2:-}" v; read -r "v?$p${d:+ [$d]}: " || true; echo "${v:-$d}"; }

echo "== loom-start Step 2b — loop.config.json (writes into $(pwd)) =="
PROJECT=$(ask "Project name" "$(basename "$(pwd)")")
MODE=$(ask "Mode (new = scaffold fresh folders / existing = use what's here)" "new")
AUTO=$(ask "Autonomy (L1 report / L2 assisted / L3 unattended)" "L1")

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

PROJECT="$PROJECT" MODE="$MODE" AUTO="$AUTO" SVCS="$SVC_LINES" node <<'NODE'
const fs = require('fs');
const svcs = (process.env.SVCS || '').split('\n').filter(Boolean).map(l => {
  const [id, side, path, stack] = l.split('|');
  return { id, side, path, stack };
});
const cfg = {
  project: process.env.PROJECT,
  mode: process.env.MODE,
  services: svcs,
  autonomy: process.env.AUTO
};
fs.writeFileSync('loop.config.json', JSON.stringify(cfg, null, 2) + '\n');
console.log('\nWrote loop.config.json with ' + svcs.length + ' service(s).');
NODE

echo "Next: node tools/cfg.js resolved   (review)   then   zsh tools/scaffold-all.sh   (scaffold, if mode=new)"
