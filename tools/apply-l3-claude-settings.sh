#!/usr/bin/env zsh
# apply-l3-claude-settings.sh — write control-folder .claude/settings.local.json for L3 sessions.
# Usage (from control folder): zsh "$(cat ~/.loop-base)/tools/apply-l3-claude-settings.sh"
set -euo pipefail
SELF_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="loop.config.json"
[ -f "$CFG" ] || { echo "run from control folder with $CFG" >&2; exit 1; }
AUTO="$(node -e "console.log(JSON.parse(require('fs').readFileSync('loop.config.json','utf8')).autonomy||'L1')")"
[ "$AUTO" = "L3" ] || { echo "autonomy is $AUTO — not writing L3 settings" >&2; exit 1; }

mkdir -p .claude
cat > .claude/settings.local.json <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Edit(*)",
      "Write(*)",
      "Read(*)",
      "Glob(*)",
      "Grep(*)"
    ],
    "deny": [
      "Bash(git push --force *)",
      "Bash(git push -f *)",
      "Bash(git reset --hard *)",
      "Bash(rm -rf *)",
      "Read(.env)",
      "Read(.env.*)",
      "Edit(.env)",
      "Edit(.env.*)",
      "Write(.env)",
      "Write(.env.*)"
    ]
  }
}
JSON
echo "✓ wrote .claude/settings.local.json (L3 permissive + denylist)"
echo "  Note: service repos outside this folder still rely on install-l3-hooks.sh (global PermissionRequest hook)."
