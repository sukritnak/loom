# Browser QA — `browser-use` vs local CDP

> **FE/UI only.** Backend AC (API, DB, jobs) → `loom-qa` uses **tests, curl, integration scripts** — no browser, no gate, no `BROWSER_USE_API_KEY`.  
> **FE perf (Lighthouse):** `perf-lighthouse` on **`loom-fe` / `loom-motion` only** — not BE.  
> Browser stack runs **only** when acceptance criteria mention UI, layout, flows, or browser behavior.

`loom-qa` verifies **FE/UI** acceptance criteria in a **real browser**. Loom supports two backends:

| Mode (`qa_browser`) | Backend | Best for |
|---------------------|---------|----------|
| **`local-cdp`** | [chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp) (or Cursor `cursor-ide-browser`) | `localhost` dev server, no API key, no tunnel |
| **`browser-use`** | [browser-use](https://github.com/browser-use/browser-use) + `browser-harness` | Clean cloud browser, isolated session |
| **`auto`** (default) | local-cdp if MCP installed, else browser-use | Most machines after `init.sh` |

Set in `loop.config.json` → `qa_browser` and/or `STATE.md` → `## Browser QA`.

---

## Install (once per machine)

```zsh
git pull && zsh tools/refresh.sh   # agents + chrome-devtools-mcp (every pull)
zsh tools/init.sh                  # + all external skills (optional)
```

| Component | When |
|-----------|------|
| chrome-devtools-mcp | **`refresh.sh` every pull** — default `qa_browser: auto` → local |
| qa-browser skill | `init.sh` or first `install-browser-qa.sh` |
| `BROWSER_USE_API_KEY` | **Only if** you pick cloud `browser-use` — orch asks A/B/C at QA time |

---

## Runtime gate (before QA in the loop)

When orch reaches **Verify** with UI AC, run (or mirror in chat):

```zsh
zsh "$(cat ~/.loop-base)/tools/qa-browser-gate.sh" gate
```

If `browser-use` is selected but no key:

| Option | Action |
|--------|--------|
| **A** | Paste `BROWSER_USE_API_KEY` → saved to `~/.loom/browser-use.env` |
| **B** | Agent self-signup (free key via browser-use challenge — see qa skill) |
| **C** | Switch to **`local-cdp`** + run `install-chrome-devtools-mcp.sh` |

Orch **must not** delegate UI browser QA until gate returns `ready`.

---

## `BROWSER_USE_API_KEY` — when?

| Mode | Key required? |
|------|----------------|
| `local-cdp` | **No** |
| `browser-use` | **Yes** (cloud browser) |
| `auto` + local MCP present | **No** |

Where to put it (pick one):

1. **Runtime gate (recommended)** — option A above → `~/.loom/browser-use.env`
2. **Shell** — `export BROWSER_USE_API_KEY=bu_…` in your profile
3. **At QA time** — paste when `loom-qa` asks (orch gate option A)

Get a key: https://cloud.browser-use.com/new-api-key

**Never commit keys.** Saved to `~/.loom/browser-use.env` (mode `700`, file `600`) with `~/.loom/.gitignore`. Control folders get `.gitignore` via `ensure-control-gitignore.sh` at `loom-start`.

---

## What `loom-qa` does per mode

### `local-cdp`

- Open dev URL from `STATE.md` → `## Dev URLs` (no ngrok tunnel)
- Use **chrome-devtools-mcp** tools (`navigate_page`, snapshot, click, …) or **cursor-ide-browser** on Cursor
- PASS/FAIL per AC with snapshot or console evidence

### `browser-use`

- Load **`qa-browser`** skill → `browser-harness` + cloud browser
- Tunnel `localhost` when needed (see skill `references/methodology.md`)
- Score **1–5** + evidence per AC

---

## Config example

```json
{
  "qa_browser": "auto"
}
```

Values: `auto` | `browser-use` | `local-cdp`
