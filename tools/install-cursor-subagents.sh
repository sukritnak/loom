#!/usr/bin/env zsh
# install-cursor-subagents.sh — sync Loom agents into Cursor Subagents + purge stale IDs.
#   Project (higher priority): <blueprint>/.cursor/agents/ → symlinks to .claude/agents/
#   User (all projects):        ~/.cursor/agents/            → copies from .claude/agents/
# Also clears Cursor's cached subagent list (old loop-* / pm / be names).
# Usage: zsh tools/install-cursor-subagents.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/.claude/agents"
USER_AGENTS="$HOME/.cursor/agents"
PROJ_AGENTS="$ROOT/.cursor/agents"

if ! command -v cursor >/dev/null 2>&1 && [[ ! -d "$HOME/.cursor" ]]; then
  echo "  (skip Cursor subagents — Cursor not detected)"
  exit 0
fi

ls "$SRC"/*.md >/dev/null 2>&1 || { echo "no agents in $SRC"; exit 1; }

# Pre-rename IDs and filenames (Settings UI may still list these until cache is cleared)
OLD_IDS=(loop-start loop-orch pm design fe fe-anim be be-sr qa)
OLD_FILES=(
  loop-start.md tech-loop-orchestrator.md designer-agent.md
  frontend-animation-agent.md backend-senior-agent.md
)

purge_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  setopt null_glob 2>/dev/null || true
  for id in "${OLD_IDS[@]}"; do rm -f "$dir/$id.md"; done
  for f in "${OLD_FILES[@]}"; do rm -f "$dir/$f"; done
  # orphan wipe: only remove files whose frontmatter name is a pre-rename ID
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    name="$(awk '/^---$/{n++; next} n==1 && /^name:/{print $2; exit}' "$f" 2>/dev/null || true)"
    for id in "${OLD_IDS[@]}"; do
      [[ "$name" == "$id" ]] && rm -f "$f" && break
    done
  done
  unsetopt null_glob 2>/dev/null || true
}

echo "== Cursor subagents (loom-*) =="
purge_dir "$USER_AGENTS"
purge_dir "$PROJ_AGENTS"

mkdir -p "$USER_AGENTS"
setopt null_glob 2>/dev/null || true
rm -f "$USER_AGENTS"/*.md
unsetopt null_glob 2>/dev/null || true
cp -f "$SRC"/*.md "$USER_AGENTS/"
echo "  ✓ user     → ~/.cursor/agents/  ($(ls "$USER_AGENTS"/*.md | wc -l | tr -d ' ') files)"

mkdir -p "$PROJ_AGENTS"
setopt null_glob 2>/dev/null || true
rm -f "$PROJ_AGENTS"/*.md
unsetopt null_glob 2>/dev/null || true
for f in "$SRC"/*.md; do
  ln -sf "../../.claude/agents/$(basename "$f")" "$PROJ_AGENTS/$(basename "$f")"
done
echo "  ✓ project  → .cursor/agents/   (symlinks → .claude/agents/)"

# Clear Cursor's cached subagent registry (reload window after)
STATE_DB="$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
if [[ -f "$STATE_DB" ]] && command -v python3 >/dev/null 2>&1; then
  python3 - "$STATE_DB" "${OLD_IDS[@]}" <<'PY'
import sqlite3, json, sys
db_path, *old_ids = sys.argv[1:]
OLD = set(old_ids)
con = sqlite3.connect(db_path)
con.execute("UPDATE ItemTable SET value='[]' WHERE key='cursor.subagents.recentlyUsed'")
row = con.execute("SELECT value FROM ItemTable WHERE key='cursor.recentlyUsed.globalOrder'").fetchone()
if row and row[0]:
    lst = json.loads(row[0])
    filtered = [x for x in lst if not (isinstance(x, dict) and x.get("type") == "subagent" and x.get("identifier") in OLD)]
    con.execute("UPDATE ItemTable SET value=? WHERE key='cursor.recentlyUsed.globalOrder'", (json.dumps(filtered),))
for (k,) in con.execute("SELECT key FROM ItemTable WHERE key LIKE 'agentData.cacheStorage.agentEnvironment.slashMenuItems.%'"):
    con.execute("DELETE FROM ItemTable WHERE key=?", (k,))
con.commit()
con.close()
print("  ✓ cleared Cursor subagent cache (reload window to refresh Settings UI)")
PY
else
  echo "  (cache clear skipped — state DB not found)"
fi

echo ""
echo "Reload Cursor: Cmd+Shift+P → Developer: Reload Window"
echo "Settings → Agents → Subagents should list loom-start, loom-orch, loom-pm, …"
