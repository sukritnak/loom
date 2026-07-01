# Handoff — Loom loop continuity

Use with **`STATE.md`** (durable) + agent **`## Handoff summary`** (per step).  
Process gates: [`loop-process.md`](loop-process.md) · Architecture: [`hexagonal-project-structure.md`](hexagonal-project-structure.md) Part E.

## Every agent return includes

```markdown
## Handoff summary
- **Goal:**
- **Done this step:**
- **Files:**
- **Verified:** <!-- required — e.g. `npm test` exit 0; orch rejects if missing when tests claimed -->
- **Open / blockers:**
- **Next:**
- **Editor:**
```

## Editor switch (Cursor ↔ Claude ↔ Hermes)

1. Finish **Handoff summary** + update `STATE.md`
2. On new machine: `zsh tools/refresh.sh` (syncs agents after pull)
3. New chat: `Use loom-orch` or paste `## Last handoff` from `STATE.md`
4. Long context: **handoff** skill → `HANDOFF.md` in control folder (optional)

## Orchestrator

- Writes agent summary → `STATE.md` → `## Last handoff`
- Sets `## Next action` + status board
- `dash.sh report` mirrors summary before closing chat turn
