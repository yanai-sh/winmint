# ADR-014: Docs are not living law

**Status:** Accepted · **Date:** 2026-08-23

### Context

A living overlay (`DESIGN.md`, module API paste, specs) restated code. Agents treated it as a second product. `DESIGN.md` claimed to outrank ADRs.

### Rejected

- Keep the overlay as law — two truths; markdown goes stale first.
- Freeze the files in tree — agents still read them as law.

### Decision

Code and tests own behaviour. Markdown holds only:

- [CONTEXT.md](../../CONTEXT.md) — words (coined terms, polarity, avoid-lists)
- `docs/decisions/` — why and rejected alternatives
- [AGENTS.md](../../AGENTS.md) — map (reach + paths; not an encyclopedia)
- `docs/agents/` — thin pointers for issue-tracker / domain-doc habit
- Human/legal pages (README, SECURITY, PRIVACY, signing) — operator policy

An ADR is the **choice** and **what was rejected**. Not an opcode list, id catalog, changelog, or API paste. Those live in code. Git history is the archive. Do not revive STACK / ARCHITECTURE / DESIGN overlays, or keep completed session-plan trees (`docs/superpowers/`, etc.) as product law — issues + git history already hold that work.

### Review trigger

A new overlay appears, ADRs grow catalogs that belong in code, or a completed plan/spec tree is left in-tree as living guidance.
