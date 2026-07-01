# Agent gate — copy into agent defs (orch / pm / be / fe / qa / fullstack)

When a row in **FE vs BE** or **test-master references** applies and `test-master` is not installed:

1. Run `zsh "$B/tools/test-master-gate.sh" status` (or `check` — exit 1 = missing).
2. If **missing** → **stop and ask** (never ask user to copy a shell command):

**Cursor — AskQuestion** (one question; option 1 = Recommended):

- Title: `Install test-master?`
- Prompt: `<one-line reason from table, e.g. "No API integration tests in this BE service">`
- **Yes — install now** *(Recommended)*
- **Not now** — continue without; ask again next time this situation comes up

**Claude Code / Hermes — A/B table:**

| **A** | Yes — install now *(recommended)* |
| **B** | Not now — ask again when needed |

3. **A / Yes** → **you** run `zsh "$B/tools/test-master-gate.sh" install` (Bash). Confirm `ready`, then load the matching reference from [test-master](https://github.com/Jeffallan/claude-skills/blob/main/skills/test-master/SKILL.md).
4. **B / Not now** → continue without the skill; **repeat steps 1–2** on the next iteration that needs it (no permanent skip).

Terminal users: `zsh "$B/tools/test-master-gate.sh" gate "reason"` — numbered menu, same choices.
