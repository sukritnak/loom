#!/usr/bin/env zsh
# Install ECC hexagonal-architecture skill → ~/.agents/skills/hexagonal-architecture
# Source: https://github.com/affaan-m/ECC/blob/main/skills/hexagonal-architecture/SKILL.md
set -euo pipefail

DEST="${HOME}/.agents/skills/hexagonal-architecture"
URL="https://raw.githubusercontent.com/affaan-m/ECC/main/skills/hexagonal-architecture/SKILL.md"

mkdir -p "$DEST"
curl -fsSL "$URL" -o "$DEST/SKILL.md"

grep -q 'hexagonal-architecture' "$DEST/SKILL.md" || { echo "  ✗ SKILL.md looks wrong" >&2; exit 1; }
echo "  ✓ hexagonal-architecture → $DEST/SKILL.md"
echo "Done. Hermes: zsh tools/install-hermes-skills.sh"
