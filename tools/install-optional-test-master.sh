#!/usr/bin/env zsh
# Optional: test-master for situational test authoring (not in default init.sh).
# Verify path unchanged — loom-qa + qa-browser/local-cdp + npm test.
#
# WHEN to run (manual only — never called by init.sh or refresh.sh):
#   - PM AC needs formal test plan / matrix
#   - BE lacks API integration test infra
#   - New project needs unit test scaffold
#   - QA hits flaky mocks / anti-patterns
#   - OWASP or load/SLO AC beyond default stack
# See: docs/test-authoring.md
set -euo pipefail
SKILLS_DIR="${HOME}/.agents/skills"
SPEC="Jeffallan/claude-skills@test-master"

if [ -f "$SKILLS_DIR/test-master/SKILL.md" ]; then
  echo "  ✓ test-master already installed"
  exit 0
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "  ✗ npx required — or: npx skills add $SPEC -g" >&2
  exit 1
fi

echo "== optional: test-master =="
( cd "$HOME" && npx --yes skills add "$SPEC" -g -y ) || {
  echo "  ✗ install failed" >&2
  exit 1
}
echo "  ✓ test-master → $SKILLS_DIR/test-master/"
echo "  Guide: docs/test-authoring.md"
