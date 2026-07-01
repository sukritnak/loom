#!/usr/bin/env zsh
# Optional test-master install gate — agent asks user; script installs (no copy-paste).
# Usage:
#   test-master-gate.sh status              → installed | missing
#   test-master-gate.sh check               → exit 0 if installed
#   test-master-gate.sh install             → install skill + update STATE.md
#   test-master-gate.sh gate [reason]       → ready | NEEDS_PROMPT (non-TTY) | interactive menu
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
B="$(cat ~/.loop-base 2>/dev/null || echo "$ROOT")"
SKILLS_DIR="${HOME}/.agents/skills"
MARKER="${SKILLS_DIR}/test-master/SKILL.md"

source "$(dirname "$0")/wizard-menu.sh" 2>/dev/null || true

is_installed() { [ -f "$MARKER" ]; }

write_state() {
  local status="${1:-installed}"
  [ -f STATE.md ] || return 0
  node -e "
const fs = require('fs');
const status = process.argv[1];
let t = fs.readFileSync('STATE.md', 'utf8');
const block = '## Optional skills\n- test-master: ' + status + '\n';
if (/## Optional skills\n/.test(t)) {
  t = t.replace(/## Optional skills\n[\s\S]*?(?=\n## |\n$)/, block.trimEnd() + '\n\n');
} else {
  t = t.replace(/(## Browser QA)/, block + '\n$1');
}
fs.writeFileSync('STATE.md', t);
" "$status"
}

do_install() {
  zsh "$B/tools/install-optional-test-master.sh"
  write_state installed
  echo "STATUS=installed"
  echo ready
}

CMD="${1:-status}"
REASON="${2:-test authoring helpers would help this step}"

case "$CMD" in
  status)
    if is_installed; then echo installed; else echo missing; fi
    ;;
  check)
    is_installed
    ;;
  install)
    do_install
    ;;
  gate)
    if is_installed; then
      echo "STATUS=installed"
      echo ready
      exit 0
    fi
    if [ -t 0 ]; then
      echo ""
      echo "test-master (optional) — $REASON"
      echo "  Guide: $B/docs/test-authoring.md"
      echo ""
      case "$(menu_pick "Install test-master?" 1 \
        "A — Yes, install now" \
        "B — Not now (ask again when needed)")" in
        A*|Yes*)
          do_install
          ;;
        *)
          write_state not-installed
          echo "STATUS=skipped"
          ;;
      esac
    else
      echo "STATUS=missing"
      echo "REASON=$REASON"
      echo NEEDS_PROMPT
      exit 1
    fi
    ;;
  *)
    echo "usage: test-master-gate.sh status|check|install|gate [reason]" >&2
    exit 2
    ;;
esac
