#!/usr/bin/env bash
# Interactive wizard — writes loop.config.json in the CURRENT folder (the project root).
# Supports MANY FE and BE folders. Run: bash tools/init-config.sh  (or: make setup)
set -euo pipefail

ask() { local p="$1" d="${2:-}" v; read -r -p "$p${d:+ [$d]}: " v || true; echo "${v:-$d}"; }

echo "== loop.config.json setup (writes into $(pwd)) =="
PROJECT=$(ask "Project name" "$(basename "$(pwd)")")
MODE=$(ask "Mode (new = scaffold fresh folders / existing = use what's here)" "new")
AUTO=$(ask "Autonomy (L1 report / L2 assisted / L3 unattended)" "L1")

echo
echo "Service paths are relative to THIS folder (e.g. 'web', 'apps/api') or absolute."
echo "Add as many FE and BE folders as you want. Press Enter on an empty 'id' to finish."
echo

SVC_LINES=""
while true; do
  echo "-- new service --"
  ID=$(ask "  service id (blank = done)" "")
  [ -z "$ID" ] && break
  SIDE=$(ask "  side (fe/be)" "fe")
  if [ "$SIDE" != "fe" ] && [ "$SIDE" != "be" ]; then echo "  side must be fe or be"; continue; fi
  if [ "$SIDE" = "fe" ]; then DEFSTACK="next"; else DEFSTACK="fastapi"; fi
  PATH_=$(ask "  path" "$ID")
  STACK=$(ask "  stack hint (or blank)" "$DEFSTACK")
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
  autonomy: process.env.AUTO,
  dashboard: 'agent-dashboard'
};
fs.writeFileSync('loop.config.json', JSON.stringify(cfg, null, 2) + '\n');
console.log('\nWrote loop.config.json with ' + svcs.length + ' service(s).');
NODE

echo "Next: make config   (review)   then   make init   (scaffold, if mode=new)"
