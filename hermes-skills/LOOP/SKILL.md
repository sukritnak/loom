---
name: loop
description: Loop-engineering spec for this team — primitives (STATE.md, loop.config.json), L1/L2/L3 phases, safety denylist, iteration anatomy. Use when the user asks how the loop works, which autonomy level to use, or what the orchestrator should do between runs.
---
# LOOP — the system that prompts the agents

This team is built as a **loop**, not a one-shot chat. Following loop-engineering
(Addy Osmani; Boris Cherny / Anthropic; cobusgreyling/loop-engineering): you stop
hand-prompting agents and instead design the control system that prompts them and
decides what to do next, iterating until the goal is met or it hands back to you.

## Primitives (and where they live here)
| Primitive | In this team |
|-----------|--------------|
| State / Memory | `STATE.md` — durable spine; orchestrator reads first, writes last |
| Project map | `loop.config.json` — which FE/BE folders to work in (many services). **Not hand-written first** — `make setup` or `loop-orch` creates it on first run |
| Sub-agents (maker / checker) | makers = frontend-agent, backend-agent · checker = qa-agent |
| Worktrees | makers run in isolated git worktrees for safe parallel work |
| Skills & connectors | pm-skills, ui-ux-pro-max, context7, ponytail, browser-use qa |
| Automation / scheduling | optional: run the loop on a cadence (see "Automate") |
| Human gate | risky/ambiguous steps escalate to you with full context |

## Anatomy of one iteration
```
load STATE.md + loop.config.json (create config first if missing — ask step by step or run make setup)
   → clarify (PM) → design (Designer, if UI)
   → build in parallel worktrees (Backend + Frontend, makers)
   → verify (QA, checker: PASS/FAIL per acceptance criterion)
   → PASS? ── yes → persist STATE.md → human gate → done
              └─ no → findings back to makers, loop++ (≤3 rounds) → build again
```
Every transition is mirrored to the live dashboard via `agent-dashboard/agent-status.js`.

## Phased rollout (don't start unattended)
- **L1 — report only**: the loop plans and proposes; no commits. Run here first.
- **L2 — assisted**: makers write code in a worktree; you review and merge the diff.
- **L3 — unattended**: only after you opt in; the safety denylist stays in force.

Move up a level only once the previous one has been boring for a while.

## Safety denylist (every level)
Force-push / history rewrite · delete branches or data · edit secrets/`.env`/CI
credentials · change access controls · publish/deploy · any payment. These always
stop at the human gate.

## Run it
No `loop.config.json` yet? Start anyway — `loop-orch` asks project/mode/folders and writes the file before work.

```
# one-off, report only
Use loop-orch at L1: add email-based password reset

# assisted, makers may code in a worktree, you merge
Use loop-orch at L2: fix the flaky checkout total
```

## Automate (optional)
Turn the loop into a cadence — e.g. a daily triage that reads open issues, runs one
L1 iteration, and updates `STATE.md` + the dashboard:
> "Every weekday at 9am, run loop-orch at L1 on the top untriaged
> issue, update STATE.md, and post a one-line summary. No code changes."

## Caveats (from the source)
- Token cost grows with sub-agents and long loops — keep rounds bounded.
- Verification is still on you; unattended loops make unattended mistakes.
- Read what the loop ships — comprehension debt compounds.
