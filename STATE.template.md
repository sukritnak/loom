# STATE — durable loop memory

> The loop reads this first and writes it last, every iteration. It is the spine
> that survives between runs and conversations. Keep it short and current — delete
> stale notes rather than letting them pile up.

## Goal
<one sentence: what this loop is trying to achieve>

## Done when (termination)
<!-- Testable exit — loop stops only when ALL are true -->
- [ ] Every AC in checklist is PASS (verified by QA, not makers)
- [ ] Test suite green (or N/A documented)
- [ ] No open blocker/major findings in latest feedback round

## Autonomy level
L1 (report only)   <!-- L1 | L2 (assisted, no merge) | L3 (unattended, allowlist only) -->

## Locale
auto   <!-- en | th | auto — also in loop.config.json -->

## Agent platform
auto   <!-- auto | cursor | claude | hermes — also in loop.config.json -->

## Agent models
<!-- Per-platform model ids — also in loop.config.json agent_models -->
| Platform | Model |
|----------|-------|
| cursor | composer-2.5 |
| claude | sonnet |
| hermes | inherit |

## Improvement policy
<!-- conform = match existing style, recommend only | guided = recommend then user picks | auto = apply all recommendations -->
guided   <!-- conform | guided | auto — also in loop.config.json -->

## Pending recommendations
<!-- Makers + orch: ID | Owner | Priority | Summary | Status (pending|accepted|skipped|done) -->
| ID | Owner | Priority | Summary | Status |
|----|-------|----------|---------|--------|
| — | — | — | — | pending |

## Current task
<the feature/bug in flight>

## Task kind
<!-- feature | bug | audit-only — orch sets each iteration -->
feature

## TDD policy
<!-- logic-only (default) | off | always — also loop.config.json tdd_policy -->
logic-only

## Task scope
<!-- orch sets each iteration: full-stack | api-only | fe-only | motion-heavy | audit-only -->
scope: full-stack
makers: <!-- agents that wrote code this iteration, e.g. be, fe — empty if none yet -->
in-scope services: <!-- service ids from loop.config.json -->

## Plan
<!-- Large features only — PM batches; orch runs one batch per sub-loop -->
- [ ] Batch 1: —
- [ ] Batch 2: —

## Debug log
<!-- task_kind: bug — one line per repro experiment -->
- —

## Project context
<!-- Legacy orientation (mode: existing) — orchestrator + makers fill before first build -->
<!-- Per service: stack, layout, entry points, package.json/Makefile/Docker run commands, conventions, risks -->
| Service id | Stack | Key paths | Run / test | Notes |
|------------|-------|-----------|------------|-------|
| — | — | — | e.g. `npm run dev` · `make test` · `docker compose up` | — |

## Relevant areas for this task
<!-- Files/modules likely touched — scoped to current task only -->
- —

## Loop round
1

## Status board
| Role | State | Working on |
|------|-------|-----------|
| Orchestrator | idle | — |
| PM | idle | — |
| UX/UI | idle | — |
| Backend | idle | — |
| Frontend | idle | — |
| Fullstack | idle | — |
| QA | idle | — |

## Acceptance criteria
- [ ] <criterion 1>
- [ ] <criterion 2>

## Dev URLs
<!-- FE services under test — QA records after starting dev server -->
| Service id | URL | Command |
|------------|-----|---------|
| web | http://localhost:5173 | npm run dev |

## Feedback history
<!-- PM lead writes ## Feedback round N after each QA FAIL -->
### Feedback round 1
| ID | AC | Finding | Owner | Severity | Action needed | Status |
|----|----|---------|-------|----------|---------------|--------|
| — | — | — | — | — | — | — |

## Lessons learned (Reflexion)
<!-- After each FAIL round: one line per root cause so makers don't repeat mistakes -->
- Round 1: —

## Decisions log
- <date> — <decision and why>

## Open risks / blockers
- <risk> → <who owns it>

## Next action
<the single next step the loop will take>

## Last handoff
<!-- Overwritten each agent return — compact snapshot for editor/session switches -->
- **Done:**
- **Files:**
- **Verified:** <!-- mandatory when makers ran tests/build — command + exit code -->
- **Blockers:**
- **Next:**
- **Editor:**
