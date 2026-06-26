#!/usr/bin/env zsh
# Install `loom` CLI to ~/.local/bin (idempotent).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/bin/loom"
BIN_DIR="${HOME}/.local/bin"

[[ -x "$SRC" ]] || chmod +x "$SRC"
mkdir -p "$BIN_DIR"
ln -sf "$SRC" "$BIN_DIR/loom"
echo "  ✓ loom CLI → $BIN_DIR/loom"

case ":${PATH:-}:" in
  *:"$BIN_DIR":*) ;;
  *)
    echo "  hint: add to PATH — export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac
