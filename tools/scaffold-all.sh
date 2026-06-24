#!/usr/bin/env zsh
# Scaffold service folders from loop.config.json. Run from the PROJECT (control) folder.
# Tools live in the Base blueprint; this script finds its siblings next to itself,
# while loop.config.json is read from the current folder (cwd).
#   zsh "<base>/tools/scaffold-all.sh"        # verify access, then scaffold ALL services
#   zsh "<base>/tools/scaffold-all.sh" <id>   # scaffold a single service by id
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cfg() { node "$HERE/cfg.js" "$@"; }
ONE="${1:-}"

zsh "$HERE/verify-paths.sh" || true
echo
cfg resolved | while IFS=$'\t' read -r id side path stack; do
  [ -z "$id" ] && continue
  [ -n "$ONE" ] && [ "$ONE" != "$id" ] && continue
  echo "── $id ($side) → $path [$stack]"
  zsh "$HERE/scaffold.sh" "$side" "$path" "$stack"
done
echo "scaffold complete"
