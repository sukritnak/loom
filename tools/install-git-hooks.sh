#!/usr/bin/env zsh
# install-git-hooks.sh — refresh CLI + hooks after git pull/checkout (idempotent).
# Usage: zsh tools/install-git-hooks.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$ROOT/.git/hooks"

[[ -d "$ROOT/.git" ]] || exit 0

mkdir -p "$HOOKS_DIR"

install_hook() {
  local name="$1"
  local path="$HOOKS_DIR/$name"
  local marker="# loom-refresh"
  if [[ -f "$path" ]] && ! /usr/bin/grep -q "$marker" "$path" 2>/dev/null; then
    return 0
  fi
  /bin/cat > "$path" <<EOF
#!/bin/sh
$marker
ROOT="\$(CDPATH= cd -- "\$(dirname "\$0")/../.." && pwd)"
[ -f "\$ROOT/tools/refresh.sh" ] || exit 0
exec zsh "\$ROOT/tools/refresh.sh" --git-hook
EOF
  /bin/chmod +x "$path"
}

install_hook post-merge
install_hook post-checkout

echo "  ✓ git hooks → post-merge, post-checkout (auto-refresh after pull)"
