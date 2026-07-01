#!/usr/bin/env zsh
# ~/.loom — machine-local Loom data. Always gitignore secrets (idempotent).
set -euo pipefail
LOOM_DIR="${HOME}/.loom"
mkdir -p "$LOOM_DIR"
cat >"${LOOM_DIR}/.gitignore" <<'EOF'
# Loom machine-local secrets — never commit
browser-use.env
.env
.env.*
!.gitignore
EOF
chmod 700 "$LOOM_DIR" 2>/dev/null || true
