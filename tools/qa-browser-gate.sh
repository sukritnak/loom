#!/usr/bin/env zsh
# Resolve browser QA backend; interactive gate when browser-use needs a key.
# Usage: zsh qa-browser-gate.sh [check|gate|mode]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
B="$(cat ~/.loop-base 2>/dev/null || echo "$ROOT")"
LOOM_DIR="${HOME}/.loom"
ENV_FILE="${LOOM_DIR}/browser-use.env"
mkdir -p "$LOOM_DIR"
zsh "$(dirname "$0")/ensure-loom-home.sh" >/dev/null 2>&1 || true

[ -f "$ENV_FILE" ] && set -a && source "$ENV_FILE" && set +a

source "$(dirname "$0")/wizard-menu.sh"

cfg_get() {
  [ -f loop.config.json ] && node "$B/tools/cfg.js" get "$1" 2>/dev/null || true
}

has_local_cdp() {
  [ -f "$HOME/.cursor/mcp.json" ] && grep -q 'chrome-devtools' "$HOME/.cursor/mcp.json" 2>/dev/null && return 0
  command -v claude >/dev/null 2>&1 && claude mcp list 2>/dev/null | grep -q 'chrome-devtools' && return 0
  return 1
}

ensure_local_cdp() {
  has_local_cdp && return 0
  echo "  → installing chrome-devtools-mcp…"
  zsh "$B/tools/install-chrome-devtools-mcp.sh"
  has_local_cdp
}

has_browser_use_key() { [ -n "${BROWSER_USE_API_KEY:-}" ]; }

has_qa_skill() {
  [ -f "${HOME}/.agents/skills/qa/SKILL.md" ] || \
  [ -f "${HOME}/.agents/skills/loom-qa/SKILL.md" ]
}

resolve_mode() {
  local pref="${1:-$(cfg_get qa_browser)}"
  pref="${pref:-auto}"
  case "$pref" in
    local-cdp|local) echo local-cdp ;;
    browser-use|cloud) echo browser-use ;;
    auto)
      ensure_local_cdp || true
      if has_local_cdp; then echo local-cdp; else echo browser-use; fi
      ;;
    *) echo browser-use ;;
  esac
}

save_key() {
  umask 077
  zsh "$(dirname "$0")/ensure-loom-home.sh" >/dev/null
  printf 'BROWSER_USE_API_KEY=%s\n' "$1" >"$ENV_FILE"
  chmod 600 "$ENV_FILE" 2>/dev/null || true
  export BROWSER_USE_API_KEY="$1"
  echo "  ✓ saved → $ENV_FILE"
}

write_state() {
  [ -f STATE.md ] || return 0
  node -e "
const fs = require('fs');
const [mode, status] = process.argv.slice(1);
let t = fs.readFileSync('STATE.md', 'utf8');
const block = '## Browser QA\n- mode: ' + mode + '\n- status: ' + status + '\n';
if (/## Browser QA\n/.test(t)) {
  t = t.replace(/## Browser QA\n[\s\S]*?(?=\n## |\n$)/, block.trimEnd() + '\n\n');
} else {
  t = t.replace(/(## Dev URLs)/, block + '\n$1');
}
fs.writeFileSync('STATE.md', t);
" "$1" "$2"
}

set_qa_browser_config() {
  [ -f loop.config.json ] || return 0
  node -e "
const fs=require('fs'); const c=JSON.parse(fs.readFileSync('loop.config.json'));
c.qa_browser=process.argv[1]; fs.writeFileSync('loop.config.json', JSON.stringify(c,null,2)+'\n');
" "$1"
}

interactive_gate() {
  local mode="$1"

  if [ "$mode" = local-cdp ]; then
    ensure_local_cdp || { echo "Reload editor after MCP install (Cursor: Reload Window)." >&2; return 1; }
    return 0
  fi

  if has_browser_use_key; then return 0; fi
  has_qa_skill || zsh "$B/tools/install-browser-use-qa.sh"

  if [ ! -t 0 ]; then
    echo "BLOCKED: browser-use needs BROWSER_USE_API_KEY" >&2
    echo "  zsh \"\$B/tools/qa-browser-gate.sh\" gate   OR   qa_browser: local-cdp" >&2
    return 1
  fi

  echo ""
  echo "Browser QA (browser-use) needs BROWSER_USE_API_KEY"
  echo "  https://cloud.browser-use.com/new-api-key"
  echo ""
  case "$(menu_pick "Choose" 1 \
    "A — Paste API key (→ ~/.loom/browser-use.env)" \
    "B — Agent self-signup (loom-qa, no paste)" \
    "C — Switch to local-cdp (chrome-devtools-mcp)")" in
    A*)
      local k
      read -r "k?Paste BROWSER_USE_API_KEY: " || true
      [ -n "$k" ] || return 1
      save_key "$k"
      ;;
    B*)
      echo "  → loom-qa uses qa skill self-signup (step 0)"
      ;;
    C*)
      set_qa_browser_config local-cdp
      zsh "$B/tools/install-chrome-devtools-mcp.sh"
      MODE=local-cdp
      write_state local-cdp ready
      echo "MODE=local-cdp"
      echo ready
      exit 0
      ;;
  esac
}

CMD="${1:-gate}"
MODE="$(resolve_mode)"

case "$CMD" in
  mode) echo "$MODE"; exit 0 ;;
  check)
    case "$MODE" in
      local-cdp) has_local_cdp ;;
      browser-use) has_qa_skill && { has_browser_use_key || true; }; exit 0 ;;
    esac
    ;;
  gate)
    interactive_gate "$MODE" || exit 1
    write_state "$MODE" ready
    echo "MODE=$MODE"
    echo ready
    ;;
  save-key)
    [ -n "${2:-}" ] || { echo "usage: qa-browser-gate.sh save-key bu_…" >&2; exit 2; }
    save_key "$2"
    write_state browser-use ready
    echo "MODE=browser-use"
    echo ready
    ;;
  *) echo "usage: qa-browser-gate.sh check|gate|mode" >&2; exit 2 ;;
esac
