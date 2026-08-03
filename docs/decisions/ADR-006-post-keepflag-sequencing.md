# ADR-006: Post–keep-flag sequencing (M1 Smoke before M2)

**Status:** Accepted  
**Date:** 2026-08-04  
**Grill:** [post-M1 decisions](../DESIGN.md#decisions-locked-grill) (2026-08-04)

### Context

Tickets **01–13** (M1 Smoke stack + keep-flag AppX vertical) are implemented. Keep-flag code landed after ticket **10** harness work, but maintainer Hyper-V Smoke on a real Source ISO may still be outstanding. Competing next steps: expand keep-flag (capabilities, presets, recommended remove set), open Wizard (M2), or metal job kinds (winget).

### Decision

1. **M1 exit first** — one maintainer `just smoke` green on a real Source ISO before Wizard or keep-flag expansion. Fixture-only S4 (`Category=S4`) does not count as M1 exit.
2. **Thin tickets (14+)** — no mega-epic; fold carry/ponytail into owning cards.
3. **Wizard after M1 green** — second BuildPlan host only; UI may expand presets → remove-list; Profile remains the expanded list ([ADR-005](ADR-005-keep-flag-matrix.md)).
4. **Keep-flag expansion deferred** — capabilities/features, schema `v2`, Profile presets, leftover confidence, CDM-as-primary, and any default/auto remove-list stay out until after Wizard (or a later explicit rescope). Curated catalog stays; Smoke acceptance Profile stays empty remove-list.
5. **Metal job kinds** — after Wizard **or** after M1 Smoke (whichever is second chronologically once M1 is green). First metal kind = `winget` only; stubs + fail-closed unknown kinds until then.
6. **Hardware acceptance** — M4; stricter evidence bars only; same Supervisor / settle / jobs (no fork).

### Consequences

- [ROADMAP](../ROADMAP.md) / [TICKETS](../TICKETS.md) next card = **14** (maintainer Smoke prove-out).
- Do not label keep-flag expansion or Wizard `ready-for-agent` until **14** is green (unless maintainer rescopes).

### Review trigger

M1 Smoke green on real ISO; or maintainer explicitly rescopes to Wizard-first.
