#!/usr/bin/env zsh
# hook-doctor.sh — verify dashboard hooks end-to-end.
# Usage: zsh tools/hook-doctor.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
B="$(cat "$HOME/.loop-base" 2>/dev/null || echo "$ROOT")"
B="${B%/}"
BRIDGE="$B/agent-dashboard/dash-bridge.js"
ok=0 fail=0

pass() { echo "  ✓ $1"; ok=$((ok + 1)); }
bad() { echo "  ✗ $1"; fail=$((fail + 1)); }

echo "== Loom hook doctor =="
echo "  blueprint: $B"

if [[ -f "$HOME/.loop-base" ]]; then pass "~/.loop-base"; else bad "~/.loop-base missing — run ./loom where"; fi
if [[ -x "$HOME/.local/bin/loom" ]] || [[ -x "$ROOT/loom" ]]; then pass "loom CLI"; else bad "loom CLI"; fi
if zsh "$B/tools/dash.sh" up >/dev/null 2>&1; then pass "dashboard up ($(zsh "$B/tools/dash.sh" up))"; else bad "dashboard not running — run: loom dash serve"; fi

if [[ -f "$HOME/.cursor/hooks.json" ]] && grep -q dash-bridge "$HOME/.cursor/hooks.json" 2>/dev/null; then
  pass "Cursor hooks"
else
  bad "Cursor hooks — run: zsh tools/refresh.sh"
fi

if [[ -f "$HOME/.claude/settings.json" ]] && grep -q dash-bridge "$HOME/.claude/settings.json" 2>/dev/null; then
  pass "Claude Code hooks"
else
  echo "  - Claude Code hooks (optional)"
fi

if [[ -f "$HOME/.hermes/config.yaml" ]] && grep -q dash-bridge "$HOME/.hermes/config.yaml" 2>/dev/null; then
  pass "Hermes hooks"
else
  echo "  - Hermes hooks (optional)"
fi

if [[ -f "$B/.active-project" ]]; then
  active="$(head -n1 "$B/.active-project")"
  if [[ -f "$active/loop.config.json" ]]; then
    pass "active project → $(basename "$active")"
  else
    bad ".active-project stale — run Use loom-start"
  fi
else
  echo "  - no .active-project (run Use loom-start to pick a job)"
fi

node "$BRIDGE" --self-check >/dev/null 2>&1 && pass "dash-bridge self-check" || bad "dash-bridge self-check"

SID="doctor-$$"
PARENT="doctor-parent-$$"
rm -f "$HOME/.loop-dash/${SID}.json" "$HOME/.loop-dash/${PARENT}.json"
before=$(node -e "try{console.log(JSON.parse(require('fs').readFileSync('$B/agent-dashboard/status.json')).log.length)}catch(e){console.log(0)}")

# Cursor path
echo '{"conversation_id":"'"$PARENT"'","prompt":"Use loom-start","cwd":"'"$B"'"}' \
  | node "$BRIDGE" beforeSubmitPrompt >/dev/null
echo '{"parent_conversation_id":"'"$PARENT"'","subagent_id":"sub-fe","subagent_type":"loom-fe","task":"review API","cwd":"'"$B"'"}' \
  | node "$BRIDGE" subagentStart >/dev/null
echo '{"parent_conversation_id":"'"$PARENT"'","tool_name":"StrReplace","tool_input":{"path":"README.md","old_string":"DOC_X","new_string":"DOC_Y"},"cwd":"'"$B"'"}' \
  | node "$BRIDGE" postToolUse >/dev/null
cursor_who=$(node -e "const j=JSON.parse(require('fs').readFileSync('$B/agent-dashboard/status.json'));const e=j.log.slice(-1)[0];console.log(e&&e.who||'')")
[[ "$cursor_who" == "fe" ]] && pass "Cursor subagent → fe on dashboard" || bad "Cursor subagent who=$cursor_who (expected fe)"

# Claude Code path
echo '{"hook_event_name":"UserPromptSubmit","session_id":"'"$SID"'","prompt":"Use loom-orch"}' \
  | node "$B/agent-dashboard/cc-dash-bridge.js" >/dev/null
echo '{"hook_event_name":"PostToolUse","session_id":"'"$SID"'","agent_type":"loom-be","tool_name":"Bash","tool_input":{"command":"npm test"},"cwd":"'"$B"'"}' \
  | node "$B/agent-dashboard/cc-dash-bridge.js" >/dev/null
cc_who=$(node -e "const j=JSON.parse(require('fs').readFileSync('$B/agent-dashboard/status.json'));const e=j.log.slice(-1)[0];console.log(e&&e.who||'')")
[[ "$cc_who" == "be" ]] && pass "Claude Code agent_type → be on dashboard" || bad "Claude Code who=$cc_who (expected be)"

# Hermes path
echo '{"hook_event_name":"pre_llm_call","session_id":"hermes-'"$$"'","extra":{"user_message":"/loom-orch"}}' \
  | node "$BRIDGE" >/dev/null
HID="hermes-$$"
echo '{"hook_event_name":"subagent_start","session_id":"'"$HID"'","extra":{"child_role":"loom-qa","child_goal":"verify AC"}}' \
  | node "$BRIDGE" >/dev/null
echo '{"hook_event_name":"post_tool_call","session_id":"'"$HID"'","extra":{"child_role":"loom-qa"},"tool_name":"terminal","tool_input":{"command":"npm test"},"cwd":"'"$B"'"}' \
  | node "$BRIDGE" >/dev/null
hermes_who=$(node -e "const j=JSON.parse(require('fs').readFileSync('$B/agent-dashboard/status.json'));const e=j.log.slice(-1)[0];console.log(e&&e.who||'')")
[[ "$hermes_who" == "qa" ]] && pass "Hermes child_role → qa on dashboard" || bad "Hermes who=$hermes_who (expected qa)"

active=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$HOME/.loop-dash/${PARENT}.json')).loomActive)" 2>/dev/null || echo false)
after=$(node -e "try{console.log(JSON.parse(require('fs').readFileSync('$B/agent-dashboard/status.json')).log.length)}catch(e){console.log(0)}")
[[ "$active" == "true" ]] && pass "session loomActive" || bad "session not activated"
[[ "$after" -gt "$before" ]] && pass "dashboard log grew ($before → $after)" || bad "dashboard log unchanged"

echo ""
echo "  $ok passed, $fail failed"
if (( fail )); then
  echo "  Debug: LOOM_DASH_DEBUG=1 — then retry; read ~/.loop-dash/hook-debug.log"
  echo "  Restart Cursor / Claude / Hermes after refresh.sh"
  exit 1
fi
echo "  Hooks → dashboard pipeline OK"
