# ADR-014: Docs are not living law

**Status:** Accepted · **Date:** 2026-08-23

### Context

A living overlay (`DESIGN.md`, module API paste, specs) restated code. Agents treated it as a second product. `DESIGN.md` claimed to outrank ADRs.

### Rejected

- Keep the overlay as law — two truths; markdown goes stale first.
- Freeze the files in tree — agents still read them as law.

### Decision

Code and tests own behaviour. Markdown holds only:

- [CONTEXT.md](../../CONTEXT.md) — words
- `docs/decisions/` — why and rejected alternatives
- [AGENTS.md](../../AGENTS.md) — map
- Human/legal pages (README, SECURITY, PRIVACY, signing) — operator policy

An ADR is the **choice** and **what was rejected**. Not an opcode list, id catalog, changelog, or API paste. Those live in code. Git history is the archive.

### Review trigger

A new overlay appears, or ADRs grow catalogs that belong in code.
