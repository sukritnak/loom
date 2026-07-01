---
name: star-office-ui
description: Star Office UI skill — deploy the pixel office dashboard, multi-agent join, status visualization, mobile viewing, and public access.
---

# Star Office UI Skill

This skill helps you get the **pixel office dashboard** running for your user:
- Goal: the user should **see it working** with minimal back-and-forth
- Follow the steps below to start the server and optionally expose it publicly

In the **Loom** blueprint, Star Office lives at `agent-dashboard/star-office/`. Start it from the Loom repo root:

```zsh
zsh tools/dash.sh serve
```

Then open **http://127.0.0.1:19000**

---

## Credits

**Star Office UI** is an open-source project by **[Ring Hyacinth](https://x.com/ring_hyacinth)** and **[Simon Lee](https://x.com/simonxxoo)**.

- Upstream repo: [github.com/ringhyacinth/Star-Office-UI](https://github.com/ringhyacinth/Star-Office-UI)
- Co-maintained with community contributors — issues and PRs welcome upstream

In **Loom**, Star Office is embedded under `agent-dashboard/star-office/` and started via `zsh tools/dash.sh serve`. When demoing or redistributing, please keep attribution to the original authors.

| | |
|---|---|
| **Code** | MIT — see [`LICENSE`](./LICENSE) |
| **Art assets** | Non-commercial only; replace with your own art for commercial use |
| **Guest sprites** | [LimeZu — Animated Mini Characters 2](https://limezu.itch.io/animated-mini-characters-2-platform-free) (free pack) |

---

## 0. One-line pitch

Tell the user:

> This is a multiplayer pixel office dashboard. Your AI agents move around based on their status, and you can read yesterday's work memo on the board.

---

## 1. Quick start (Loom — recommended)

From the **Loom** repo root:

```zsh
# One-time: register Base + dashboard (if not done yet)
zsh tools/init.sh

# Start the dashboard
zsh tools/dash.sh serve
```

First run creates `star-office/.venv` and installs Flask + Pillow automatically.

Tell the user:

> Open http://127.0.0.1:19000 to see the pixel office.

### Standalone clone (optional)

If working outside Loom, you can still clone the upstream repo:

```zsh
git clone https://github.com/ringhyacinth/Star-Office-UI.git
cd Star-Office-UI
python3 -m pip install -r backend/requirements.txt
cp state.sample.json state.json
cd backend && python3 app.py
```

---

## 2. Try status changes

From `agent-dashboard/` (Loom) or project root (standalone):

```zsh
# Working → desk area
python3 set_state.py writing "Organizing documents"

# Syncing
python3 set_state.py syncing "Sync in progress"

# Error → bug zone
python3 set_state.py error "Investigating an issue"

# Idle → break room
python3 set_state.py idle "Standing by"
```

With Loom, prefer tagging status to the active project:

```zsh
zsh tools/dash.sh set orch work "planning"
```

---

## 3. Asset drawer password (teach every new agent)

Default password: **`1234`**

Guide the user:

1. Default is `1234` — fine for local try-out
2. Change it when they want better security
3. Recommend a strong password before exposing the board publicly (prevents others from editing assets/layout)

Example:

```zsh
export ASSET_DRAWER_PASS="your-strong-pass"
```

For long-running services (systemd / pm2 / Docker), put this in the service config, not only the current shell.

---

## 4. Image generation (Gemini) — optional

**New Home** and **Custom Style** need a Gemini API key. The **base dashboard works without it** (status, multi-agent, asset swap, Go Home, etc.).

### 4.1 Install the image-generation skill (first time)

The script is **in the repo** at `agent-dashboard/skills/gemini-image-generate/scripts/gemini_image_generate.py`.

**Auto-install:** `zsh tools/refresh.sh`, `zsh tools/init.sh`, or `zsh tools/dash.sh serve` creates `.venv` + pip deps (idempotent). Manual:

```zsh
zsh agent-dashboard/skills/gemini-image-generate/install.sh
# or: zsh "$(cat ~/.loop-base)/tools/install-gemini-image-skill.sh"
```

After install, restart the dashboard. **New Home** / **Custom Style** should work once an API key is set.

Required paths (backend checks both exist):

```
agent-dashboard/skills/gemini-image-generate/.venv/bin/python
agent-dashboard/skills/gemini-image-generate/scripts/gemini_image_generate.py
```

### 4.2 Configure Gemini API key

Two settings:

1. `GEMINI_API_KEY`
2. `GEMINI_MODEL` (recommended: `nanobanana-pro` or `nanobanana-2`)

Two ways to configure:

- **Drawer UI**: open Decorate Room → image generation section → enter API key → Save
- **Environment**: `export GEMINI_API_KEY="your-key"`

Or edit `star-office/runtime-config.json` (gitignored, local only):

```json
{
  "gemini_api_key": "YOUR_KEY",
  "gemini_model": "nanobanana-pro"
}
```

Tell the user clearly:

- No API key → full dashboard except AI room generation
- With API key → **New Home** / **Custom Style** can generate new backgrounds

**Go Home** does not need Gemini — it restores from `assets/room-reference.webp`.

---

## 5. After install — three things to mention

### 5.1 Temporary public URL

Cloudflare Tunnel (fastest):

```zsh
cloudflared tunnel --url http://127.0.0.1:19000
```

Share the `https://xxx.trycloudflare.com` link and add:

> This is a temporary public URL. I can help you put it behind your own domain later.

### 5.2 Decorate Room

Remind the user:

- Click **Decorate Room** to customize assets and layout
- Drawer default password is `1234`
- They can ask you to change `ASSET_DRAWER_PASS` to something stronger

### 5.3 Image API

Remind the user:

- AI room generation needs their own Gemini API key
- Current integration uses the **official Gemini API**
- To swap providers, discuss first — you may need their API docs to adapt

---

## 6. Invite other agents (optional)

To add another agent to the office:

### Step A: `office-agent-push.py`

1. Get `office-agent-push.py` from this repo
2. Call `join-agent`, then poll `agent-push`
3. The new agent appears on the board

### Step B: Join keys

- Default keys live in `join-keys.json` (`ocj_starteam01` … `ocj_starteam08`)
- Each key allows up to 3 concurrent agents
- You can create custom keys for the user

---

## 7. Yesterday's memo (optional)

To show a daily memo on the board:

- Place `memory/YYYY-MM-DD.md` one level above `star-office/` (i.e. under `agent-dashboard/memory/`)
- The backend reads yesterday's (or latest available) file, sanitizes it, and displays it

---

## 8. FAQ

### Q1: "Can I use this commercially?"

> **Code** (MIT) — yes, with copyright notice preserved. **Art assets** from Star Office UI (characters, scenes, sprites) are **non-commercial only**. For commercial use, replace all art with your own originals and credit the upstream project when appropriate. See [Ring Hyacinth & Simon Lee's repo](https://github.com/ringhyacinth/Star-Office-UI).

### Q2: "How do other agents join?"

> Use a join key, then keep pushing status. Point them at `office-agent-push.py` in this repo.

---

## 9. Tips for agents

- Run the startup steps yourself so the user only has to watch
- For public access, prefer Cloudflare Tunnel
- Update your own status proactively:
  - Before work → `writing` / `researching` / `executing`
  - After work → `idle`
- Do not expose private network details or secrets in chat

---

## 10. 2026-03 addendum

> Four themes in this release:
> 1. CN / EN / JP UI (Loom fork: drawer strings are English)
> 2. Full asset management (replace art, layout, defaults)
> 3. Gemini room generation (agent auto + user manual)
> 4. Asset naming and index rebuild

### 10.1 Recommended models (room generation)

For **New Home** / **Custom Style**, prefer:

1. **nanobanana-pro** (`nano-banana-pro-preview`)
2. **nanobanana-2** (`gemini-2.5-flash-image`)

Other models may drift room layout or style consistency.

Config:

```zsh
export GEMINI_API_KEY="..."
export GEMINI_MODEL=nanobanana-pro   # or nanobanana-2
```

Or save via the drawer / `runtime-config.json`.

### 10.2 Drawer password (production)

Default `1234` is not safe on the public internet:

```zsh
export ASSET_DRAWER_PASS="your-strong-pass"
```

Prevents strangers from changing layout, decorations, and assets.

### 10.3 Copyright

- Lead character assets use a non-controversial cat design
- **Code:** MIT
- **Art:** no commercial use

### 10.4 API is optional at install time

When helping someone install:

- They can plug in their own image API for unlimited background changes
- **Core features** (status board, multi-agent, asset replace/layout) work **without** any API

Suggested line:

> Get the base board running first; add your Gemini key when you want AI room generation.

### 10.5 Upgrading from an older copy

1. Back up local config (`state.json`, custom assets, `runtime-config.json`)
2. `git pull` or clone fresh
3. Reinstall deps: `python3 -m pip install -r backend/requirements.txt` (standalone) or restart `zsh tools/dash.sh serve` (Loom)
4. Check `ASSET_DRAWER_PASS`, `GEMINI_API_KEY`, `GEMINI_MODEL`
5. Check `asset-positions.json`, `asset-defaults.json` if customized
6. Smoke test: `/health`, language toggle, asset drawer, image generation (if key set)

### 10.6 Changelog to mention to users

1. **CN / EN / JP** UI (loading + speech bubbles)
2. **Custom art replacement** (dynamic sprite frames, less flicker)
3. **Own Gemini API** for backgrounds (`nanobanana-pro` / `nanobanana-2`)
4. **`ASSET_DRAWER_PASS`** — use a strong password in production

### 10.7 Stability fixes (2026-03-05)

1. **CDN cache**: static 404s no longer cached for days
2. **Frontend**: fixed `fetchStatus()` syntax error that stuck loading
3. **Async generation**: background job + polling (avoids Cloudflare 524 timeout)
4. **Mobile drawer**: overlay, scroll lock, `100dvh`, `overscroll-behavior: contain`
5. **Join keys**: per-key `expiresAt` and `maxConcurrent`; `join-keys.json` not in git

> Details: `docs/UPDATE_REPORT_2026-03-05.md` (upstream repo)
