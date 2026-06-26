# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

**Loom** is a blueprint (control-repo) — a team of 9 AI agents that run a plan→build→verify loop on your real project code. This repo is **never** where real project code lives.

## Three-layer architecture

```
Blueprint (Base = this repo)        control folder (~/.../agent-build/my-app)
────────────────────────────        ──────────────────────────────────────────
.claude/agents/  agent definitions  loop.config.json  ← services + mode + autonomy
hermes-skills/   Hermes skills      STATE.md          ← loop memory (resumable)
tools/           shared scripts
agent-dashboard/ central board
```

- **Base (this repo)** — agent definitions, shared tools, dashboard. Never copied to destinations.
- **Control folder** — one folder per job under the base folder (e.g. `~/Documents/coding/agent-build/shop`). Contains only `loop.config.json` + `STATE.md`.
- **Real code** — at `services[].path` in `loop.config.json`. Can be relative to the control folder or absolute paths pointing anywhere on disk.

**Critical rule:** Never create `loop.config.json` inside this repo or the current working directory. Projects always live under a separate base folder.

## Key commands

### Install (once per machine, run from this repo)
```zsh
zsh tools/deploy.sh                        # full install (optional — ./loom auto-bootstraps on first use)
DEPLOY_SKIP_EXTERNAL_SKILLS=1 zsh tools/deploy.sh  # skip external skill download
zsh tools/refresh.sh                       # re-sync CLI + agents + hooks (after move)
```

### Claude Code from anywhere (after deploy)
```zsh
loom wrap claude                           # cwd = blueprint; active project dirs via --add-dir if set
loom where                                 # print ~/.loop-base path
```

### Start/resume a project (chat — preferred)
```
Use loom-start       # Claude Code / Cursor
/loom-start          # Hermes
```

### Start/resume a project (terminal)
```zsh
zsh tools/loom-start.sh                    # full wizard Steps 1–4
zsh tools/new-project.sh my-app            # shortcut: create new control folder
```

### Work on a project
```
Use loom-orch at L1: <describe feature or bug>
```

### Sync agent definitions after editing `.claude/agents/*.md`
```zsh
zsh tools/sync-agents.sh    # copies to ~/.claude/agents/ + Hermes
zsh tools/install-cc-hooks.sh  # Claude Code → dashboard auto-bridge (once)
```

### Dashboard
```zsh
zsh tools/dash.sh serve     # Star-Office pixel board → http://localhost:19000
zsh tools/dash.sh where     # print board path
```

### Config utilities (run from control folder, not from Base)
```zsh
B="$(cat ~/.loop-base)"
node "$B/tools/cfg.js" resolved          # list services + resolved absolute paths
node "$B/tools/cfg.js" abspath api       # absolute path for service id=api
node "$B/tools/cfg.js" ids fe            # ids for a given side
zsh "$B/tools/verify-paths.sh"          # check folder access before any work
zsh "$B/tools/scaffold-all.sh"          # scaffold all services (mode=new only)
zsh "$B/tools/scaffold-all.sh" api      # scaffold one service by id
```

## Agent team

| Agent | Role |
|-------|------|
| `loom-start` | Bootstrap: pick/create project → write `loop.config.json` → hand off |
| `loom-orch` | Orchestrator: reads `STATE.md` + config, delegates team, runs loop |
| `loom-pm` | Requirements, acceptance criteria, QA triage lead · **loom-me** for workflow grilling |
| `loom-ux-ui` | UX/UI spec before any FE build · **ui-ux-pro-max** |
| `loom-fe` | Frontend/UI implementation |
| `loom-motion` | Animation, Three.js/WebGL |
| `loom-be` | Backend/API/data layer — **Hexagonal (Ports & Adapters, ECC)** |
| `loom-full-stack` | Fullstack (BE specialist) — DB, security, **hexagonal outbound ports**, escalation |
| `loom-qa` | Tests against AC, decides PASS/FAIL (checker — stays separate from makers) |

Agent definitions live in `.claude/agents/` (source of truth). `sync-agents.sh` pushes them to `~/.claude/agents/` (Claude Code global) and `~/.hermes/skills/` (Hermes).

## The loop flow

```
load STATE.md + loop.config.json
  → dashboard gate (ask to open http://localhost:19000)
  → legacy orient (mode:existing — explore in-scope services, mirror existing code style, /ponytail-review on touched areas)
  → clarify (PM) → design (if UI)
  → build in parallel worktrees (be + fe makers)
  → verify (QA: tests + qa-browser for FE/UI AC against dev server)
  → PASS → persist STATE.md → human gate → done
  → FAIL → PM triage → feedback packet per owner → fix → re-test (max 3 rounds)
```

**`STATE.md`** is the durable loop memory. `loom-orch` reads it first and writes it last every iteration. Keep it under ~150 lines; compact old feedback rounds into Lessons.

## `loop.config.json`

Never hand-write this in Base — `loom-start` or `zsh tools/init-config.sh` (from control folder) creates it.

```json
{
  "project": "my-app",
  "mode": "new",
  "autonomy": "L1",
  "improvement_policy": "guided",
  "services": [
    { "id": "web", "side": "fe", "path": "web",   "stack": "nextjs" },
    { "id": "api", "side": "be", "path": "api",   "stack": "nestjs" }
  ]
}
```

- `mode`: `new` = scaffold fresh folders; `existing` = operate on folders already there (no scaffold) — makers **match** existing naming, layering, and formatting in the main AC diff
- `improvement_policy`: `conform` = สไตล์เดิม แนะนำอย่างเดียว · `guided` = แนะนำแล้ว user เลือกข้อ · `auto` = แก้ตาม recommendation ทั้งหมดอัตโนมัติ (orch ถามตอน start ถ้ายังไม่ตั้ง)
- `autonomy`: L1 = report only · L2 = makers write code, you merge · L3 = unattended
- `path`: relative → under the control folder; absolute/`~` → anywhere on disk
- `side`: `fe` → owned by fe/loom-motion · `be` → owned by be/loom-full-stack

## Path resolution

Tools live only in Base and are shared by all projects via `~/.loop-base` (written by `deploy.sh`). The pattern from any control folder:

```zsh
B="$(cat ~/.loop-base)"    # resolve Base once
# then call: node "$B/tools/cfg.js" ...  / zsh "$B/tools/..."
```

`loom-orch` finds the active project by: cwd `loop.config.json` → `.active-project` pointer → asks user.

## Autonomy levels

| Level | Meaning |
|-------|---------|
| L1 | Plan/propose only — no commits. Start here. |
| L2 | Makers write in worktrees; human reviews and merges |
| L3 | Full auto. Safety denylist always applies. Run `zsh tools/install-l3-hooks.sh` once for Claude Code auto-approve. |

**Safety denylist (all levels):** force-push, delete branches/data, edit secrets/`.env`/CI, change access controls, publish/deploy, any payment.

## Platform notes

- **Claude Code** — `deploy.sh` copies agents to `~/.claude/agents/` (global, every project)
- **Cursor** — reads `.claude/agents/` directly from this repo; optional Custom Modes per agent
- **Hermes** — `deploy.sh` installs skills to `~/.hermes/skills/`; use `/loom-start`, `/loom-orch`, `/loom-be`, `/loom-qa` etc.

## Dashboard status calls

```zsh
B="$(cat ~/.loop-base)"
zsh "$B/tools/dash.sh" reset "<task title>"
zsh "$B/tools/dash.sh" set orch work "planning"
zsh "$B/tools/dash.sh" set be   done "build complete"
zsh "$B/tools/dash.sh" file be edit "src/api.ts" detail="add handler"
zsh "$B/tools/dash.sh" loop 2          # increment round
```

Agent ids: `orch pm ux-ui be fullstack fe fe-mo qa`. States: `idle | work | fix | done`.
