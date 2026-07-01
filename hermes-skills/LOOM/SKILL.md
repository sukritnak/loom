---
name: loom
description: Loom loop-engineering spec — primitives (STATE.md, loop.config.json), L1/L2/L3 phases, safety denylist, iteration anatomy. Use when the user asks how the Loom loop works, which autonomy level to use, or what loom-orch should do between runs.
---
# LOOP — the system that prompts the agents

This team is built as a **loop**, not a one-shot chat. Following loop-engineering
([Addy Osmani](https://addyo.substack.com); Boris Cherny / Anthropic; [complete guide 2026](https://tosea.ai/blog/loop-engineering-ai-agents-complete-guide-2026)):
you stop hand-prompting agents and instead design the control system that prompts them and
decides what to do next, iterating until the goal is met or it hands back to you.

## Pattern (this team)

**Orchestrator–Workers** + **Evaluator–Optimizer**: `loom-orch` delegates makers (`fe`/`be`/…)
in isolated worktrees; `qa` evaluates against AC; on FAIL, `pm` triages and the cycle repeats.
Feedback history in `STATE.md` is **Reflexion-style episodic memory** — lessons from failed
rounds that makers read before retrying.

## Primitives (and where they live here)
| Primitive | In this team |
|-----------|--------------|
| State / Memory | `STATE.md` — durable spine; orchestrator reads first, writes last |
| Project map | `loop.config.json` — which FE/BE folders to work in (many services). **Not hand-written first** — the `loom-start` skill (or `loom-orch`) creates it on first run |
| Communication locale | `loop.config.json` → `locale`: `en` \| `th` \| `auto` (match user language) — set at loom-start |
| Sub-agents (maker / checker) | makers = frontend-agent, backend-agent · checker = qa-agent |
| Worktrees | makers run in isolated git worktrees for safe parallel work |
| Skills & connectors | pm-skills, ui-ux-pro-max, context7, ponytail (+ ponytail-review, ponytail-audit on legacy), browser-use qa |
| Automation / scheduling | optional: run the loop on a cadence (see "Automate") |
| Human gate | risky/ambiguous steps escalate to you with full context |

## Anatomy of one iteration
```
load STATE.md + loop.config.json (create config first if missing — use loom-start or zsh "$(cat ~/.loop-base)/tools/init-config.sh")
   → dashboard gate — options: **A** Yes open dashboard *(recommended)* · **B** No (Cursor: AskQuestion)
   → legacy sync (mode: existing) — explore in-scope services, /ponytail-review on task-relevant code,
     /ponytail-audit only if needed; write ## Project context to STATE.md
   → bug debug gate (task_kind: bug) — repro + ## Debug log before fix — see docs/loop-process.md Gate 2
   → clarify (PM) → design (UX/UI, if UI) → ## Plan batches for large features
   → build in parallel worktrees (Backend + Frontend makers) — Verified: required in handoff
   → SR review (loom-full-stack, 2-stage: contract then ponytail) — Gate 3
   → verify (QA: unit/API tests + qa-browser for every FE/UI AC against dev server)
   → PASS? ── yes → finish checklist (Gate 5) → persist STATE.md → human gate → done
              └─ no → PM lead triage → feedback packet per owner (fe/loom-be/…)
                        → makers fix tagged items → QA re-test → loop++ (≤3 rounds)
```
Process gates (single spec): **`docs/loop-process.md`** — evidence, debug, SR, plan batches, finish.
FE/UI acceptance criteria are verified with **browser-use** (`qa-browser` skill) — real browser, not code review alone.
Install once: `zsh "$(cat ~/.loop-base)/tools/install-browser-use-qa.sh"`
Every transition is mirrored to the single central dashboard via `zsh "$(cat ~/.loop-base)/tools/dash.sh" ...`
(tools live in the blueprint; dash tags each line with the project name, so one board shows all projects/sessions).

## The three hard parts (and how we handle them)

| Problem | Fix in this team |
|---------|------------------|
| **Context** — long loops overflow the window | Externalize to `STATE.md`; prune stale notes each round; sub-agents return summaries only; use **handoff** skill between sessions |
| **Termination** — loops that never stop | Testable goal + AC in `STATE.md`; hard cap **3 feedback rounds**; human gate on round 3 FAIL; safety denylist |
| **Verification** — reward signal must be honest | **Deterministic first** (tests, lint, typecheck, build) → **browser** (`qa-browser` for FE/UI AC) → never trust maker self-report; QA decides PASS/FAIL |

## Failure modes to guard against

- **No-progress loop** — same finding ID fails twice unchanged → escalate to human immediately (don't wait for round 3).
- **Hallucinated success** — orchestrator never marks done without QA PASS on every AC.
- **Reward hacking** — makers must not delete/skip tests to pass; QA checks test count + AC intent.
- **Context rot** — if `STATE.md` grows past ~150 lines, compact Feedback history to last 2 rounds + Lessons only.

## Phased rollout (don't start unattended)
- **L1 — report only**: the loop plans and proposes; no commits. Run here first.
- **L2 — assisted**: makers write code in a worktree; you review and merge the diff.
- **L3 — unattended**: only after you opt in; the safety denylist stays in force.

Move up a level only once the previous one has been boring for a while.

## Safety denylist (every level)
Force-push / history rewrite · delete branches or data · edit secrets/`.env`/CI
credentials · change access controls · publish/deploy · any payment. These always
stop at the human gate.

## Communication locale
Set once at **loom-start** → `loop.config.json` → `locale`:
| Value | Agents use |
|-------|------------|
| `en` | English for all user-facing text |
| `th` | Thai (ไทย) |
| `auto` | Match whatever language the user writes in *(default)* |

Orchestrator passes the same rule in every delegation. Terminal: `zsh tools/loom-start.sh` asks at Step 0.5.

## Run it
No `loop.config.json` yet? Start anyway — `loom-orch` asks project/mode/folders and writes the file before work.

```
# one-off, report only
Use loom-orch at L1: add email-based password reset

# assisted, makers may code in a worktree, you merge
Use loom-orch at L2: fix the flaky checkout total
```

## Automate (optional)
Turn the loop into a cadence — e.g. a daily triage that reads open issues, runs one
L1 iteration, and updates `STATE.md` + the dashboard:
> "Every weekday at 9am, run loom-orch at L1 on the top untriaged
> issue, update STATE.md, and post a one-line summary. No code changes."

## Caveats (from the source)
- Token cost grows with sub-agents and long loops — keep rounds bounded.
- Verification is still on you; unattended loops make unattended mistakes.
- Read what the loop ships — comprehension debt compounds.
