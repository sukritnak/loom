#!/usr/bin/env zsh
# Install chrome-devtools-mcp for Loom local browser QA (idempotent).
# Cursor → ~/.cursor/mcp.json · Claude Code → claude mcp add · Hermes → print manual step
set -euo pipefail

MCP_ENTRY='{"command":"npx","args":["-y","chrome-devtools-mcp@latest"]}'
SERVER_NAME="chrome-devtools"

merge_cursor() {
  local f="$HOME/.cursor/mcp.json"
  mkdir -p "$(dirname "$f")"
  node -e "
const fs = require('fs');
const f = process.argv[1];
const name = process.argv[2];
const entry = JSON.parse(process.argv[3]);
let cfg = { mcpServers: {} };
try { cfg = JSON.parse(fs.readFileSync(f, 'utf8')); } catch (_) {}
cfg.mcpServers = cfg.mcpServers || {};
if (cfg.mcpServers[name]) {
  console.log('  ✓ Cursor MCP already has ' + name);
  process.exit(0);
}
cfg.mcpServers[name] = entry;
fs.writeFileSync(f, JSON.stringify(cfg, null, 2) + '\n');
console.log('  ✓ Cursor → ' + f);
" "$f" "$SERVER_NAME" "$MCP_ENTRY"
}

install_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    echo "  - Claude Code not found (skip MCP add)"
    return 0
  fi
  if claude mcp list 2>/dev/null | grep -q "$SERVER_NAME"; then
    echo "  ✓ Claude Code MCP already has $SERVER_NAME"
    return 0
  fi
  claude mcp add "$SERVER_NAME" --scope user npx chrome-devtools-mcp@latest && \
    echo "  ✓ Claude Code → claude mcp add $SERVER_NAME"
}

echo "== chrome-devtools-mcp (local browser QA) =="

if [ -d "$HOME/.cursor" ] || [ -n "${CURSOR_VERSION:-}" ]; then
  merge_cursor
  echo "    Reload Cursor: Cmd+Shift+P → Developer: Reload Window"
else
  echo "  - Cursor not detected (skip ~/.cursor/mcp.json)"
fi

install_claude

if command -v hermes >/dev/null 2>&1 || [ -d "$HOME/.hermes" ]; then
  echo "  ~ Hermes: add MCP server chrome-devtools → npx -y chrome-devtools-mcp@latest"
  echo "    See https://github.com/ChromeDevTools/chrome-devtools-mcp#mcp-client-configuration"
fi

echo "Done. Set loop.config.json → qa_browser: local-cdp (or auto)."
