#!/usr/bin/env zsh
# install-hermes-hooks.sh — wire Hermes shell hooks → Loom dashboard (dash-bridge.js).
# Merges into ~/.hermes/config.yaml and pre-approves hooks for non-TTY (gateway/cron).
# Skips silently when Hermes is not installed.
# Usage: zsh tools/install-hermes-hooks.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE="$ROOT/agent-dashboard/dash-bridge.js"
CONFIG="${HERMES_CONFIG:-$HOME/.hermes/config.yaml}"
ALLOWLIST="$HOME/.hermes/shell-hooks-allowlist.json"
chmod +x "$BRIDGE"

if [[ ! -f "$CONFIG" ]]; then
  if command -v hermes >/dev/null 2>&1; then
    echo "  (skip Hermes hooks — no $CONFIG; run \`hermes setup\` then re-run)"
  else
    echo "  (skip Hermes hooks — Hermes not detected)"
  fi
  exit 0
fi

if ! command -v ruby >/dev/null 2>&1; then
  echo "  (skip Hermes hooks — ruby not found; needed to merge config.yaml)"
  exit 0
fi

CMD="node $(ruby -e 'print ARGV[0].inspect' "$BRIDGE")"

ruby - "$CONFIG" "$CMD" <<'RUBY'
require "yaml"
require "json"
require "fileutils"
require "set"

config_path, bridge_cmd = ARGV
cfg = YAML.load_file(config_path) || {}
cfg["hooks"] ||= {}

loom = {
  "post_tool_call" => [
    { "matcher" => "terminal|write_file|patch", "command" => bridge_cmd, "timeout" => 15 },
  ],
  "subagent_start" => [
    { "command" => bridge_cmd, "timeout" => 15 },
  ],
  "subagent_stop" => [
    { "command" => bridge_cmd, "timeout" => 15 },
  ],
  "post_llm_call" => [
    { "command" => bridge_cmd, "timeout" => 15 },
  ],
}

marker = "dash-bridge.js"
cfg["hooks"].each do |event, entries|
  next unless entries.is_a?(Array)
  cfg["hooks"][event] = entries.reject { |e| e.is_a?(Hash) && e["command"].to_s.include?(marker) }
end

loom.each do |event, entries|
  cfg["hooks"][event] = (cfg["hooks"][event] || []) + entries
end

File.write(config_path, cfg.to_yaml)
puts "  ✓ Hermes shell hooks → dashboard bridge"
puts "    #{bridge_cmd}"
RUBY

# Pre-approve for gateway/cron (non-TTY) — exact command string must match config.
ruby - "$ALLOWLIST" "$CMD" <<'RUBY'
require "json"
require "fileutils"
require "set"

allowlist_path, bridge_cmd = ARGV
events = %w[post_tool_call subagent_start subagent_stop post_llm_call]
data = { "approvals" => [] }
if File.exist?(allowlist_path)
  begin
    data = JSON.parse(File.read(allowlist_path))
    data["approvals"] = Array(data["approvals"])
  rescue JSON::ParserError
    data = { "approvals" => [] }
  end
end
seen = data["approvals"].map { |a| [a["event"], a["command"]] }.to_set
events.each do |ev|
  pair = [ev, bridge_cmd]
  next if seen.include?(pair)
  data["approvals"] << { "event" => ev, "command" => bridge_cmd }
end
FileUtils.mkdir_p(File.dirname(allowlist_path))
File.write(allowlist_path, JSON.pretty_generate(data) + "\n")
puts "  ✓ allowlist updated (~/.hermes/shell-hooks-allowlist.json)"
RUBY

echo ""
echo "Restart Hermes CLI / gateway so hooks reload."
echo "Optional: hooks_auto_accept: true in config for CI — or use hermes --accept-hooks chat"
