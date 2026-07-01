# Test & verify — FE vs BE

Loom does **not** ship test frameworks (k6, Supertest, etc.) — those live in **your project** when makers add them.  
Agents **discover** scripts from `package.json` / `Makefile` and run what exists.

Full browser stack → [browser-qa.md](browser-qa.md).

---

## FE vs BE — what to use when

| Tool / skill | Side | Who owns | When |
|--------------|------|----------|------|
| **`local-cdp`** / **cursor-ide-browser** | **FE** | `loom-qa` | UI AC — real browser on `localhost` (Loom default after `refresh.sh`) |
| **`qa-browser`** (browser-use) | **FE** | `loom-qa` | UI AC — cloud browser + API key |
| **`perf-lighthouse`** | **FE** | `loom-fe`, `loom-motion` | CWV / Lighthouse budgets — **never BE** |
| **`npm test`**, Jest/Vitest unit | **FE** or **BE** | makers + QA | Whatever the service already has |
| **Supertest / httpx / REST Client** | **BE** | `loom-be` | API contract & integration tests |
| **curl / httpie** | **BE** | `loom-qa` | Quick API AC verify — no browser |
| **k6 / Artillery** *(project or test-master)* | **BE** | `loom-be` | Load / SLO AC — not Lighthouse |
| **`solid` + `tdd_policy`** | both | makers | Tests while building |
| **`ponytail-review` + SR** | both | `loom-full-stack` | Before QA |
| **test-master** *(optional skill)* | both | on demand | Authoring gaps only — see below |

---

## Default verify path (unchanged)

| AC type | Verify with |
|---------|-------------|
| UI / layout / flow | Browser (`local-cdp` or `qa-browser`) |
| API / DB / jobs | `npm test`, curl, integration scripts — **no browser, no gate** |
| FE performance (CWV) | `perf-lighthouse` on makers; QA may re-run if AC cites numbers |
| BE load / SLO | k6 or project load tests — not Lighthouse |

---

## test-master (optional) — agent installs on your OK

**Not** in `init.sh` / `refresh.sh`. Agents **offer a click/option** when the situation needs it; **you never copy-paste** the install command.

| Trigger | Offer install? |
|---------|----------------|
| Normal loop, tests already OK | No |
| PM AC needs formal test plan / matrix | Yes |
| BE lacks API integration tests | Yes |
| New project, no unit scaffold | Yes |
| QA flaky mocks | Yes |
| OWASP or load/SLO AC | Yes |

**Flow:** agent runs `test-master-gate.sh status` → if missing → **AskQuestion** (Cursor) or **A/B** (Claude/Hermes) → on **Yes**, agent runs `test-master-gate.sh install`. **Not now** = continue; agent asks again next time the situation appears.

Gate spec: [`docs/snippets/test-master-gate.md`](snippets/test-master-gate.md)

Skill: [test-master](https://github.com/Jeffallan/claude-skills/blob/main/skills/test-master/SKILL.md) — load **references** on demand after install.

### References by situation

| Situation | Agent | Reference | Do **not** use for |
|-----------|-------|-----------|-------------------|
| No unit test folder | `loom-be`, `loom-fe` | `unit-testing.md` | UI browser AC |
| No API/integration tests | `loom-be` | `integration-testing.md` | Replacing curl/npm test in QA |
| Flaky tests / bad mocks | `loom-qa` | `testing-anti-patterns.md` | New features |
| OWASP / penetration AC | `loom-qa`, `loom-full-stack` | `security-testing.md` | Everyday SR |
| Load / SLO AC | `loom-be` | `performance-testing.md` | FE Lighthouse |
| Formal stakeholder report | `loom-pm`, `loom-qa` | `test-reports.md` | Loop `F-1` packet |

**Skip:** `e2e-testing.md` (browser QA stack), `tdd-iron-laws.md` (`solid` + [loop-process.md](loop-process.md)).

---

## Orch / QA rule

`loom-qa` **verifies** — only **authors** tests when PM AC explicitly asks and makers did not. Route author work to `loom-be` / `loom-fe`; QA re-runs verify after.
