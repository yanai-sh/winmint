# ADR-006: Post–keep-flag sequencing (M1 Smoke before M2)

**Status:** Accepted  
**Date:** 2026-08-04  
**Grill:** post-M1 decisions (2026-08-04) — [DESIGN](../DESIGN.md#decisions-locked-grill)

### Context

Tickets **01–13** (M1 Smoke stack + keep-flag AppX vertical) are implemented. Keep-flag code landed after ticket **10** harness work, but maintainer Hyper-V Smoke on a real Source ISO may still be outstanding. Competing next steps: expand keep-flag (capabilities, presets, auto recommended set), open Wizard (M2), or metal job kinds (winget).

### Decision

1. **M1 exit first** — one maintainer `just smoke` green on a real Source ISO before Wizard or keep-flag expansion. Fixture-only S4 (`Category=S4`) does not count as M1 exit.
2. **Thin tickets (14+)** — no mega-epic; fold carry/ponytail into owning cards.
3. **Wizard after M1 green** — second BuildPlan host only; UI may expand presets → remove-list; Profile remains the expanded list ([ADR-005](ADR-005-keep-flag-matrix.md)).
4. **Keep-flag expansion deferred** — capabilities/features, schema `v2`, Profile presets, leftover confidence, and CDM-as-primary stay out until after Wizard (or a later explicit rescope). No product-default / opt-out “recommended remove set.”
5. **Acceptance remove-list (grill B4)** — Smoke **acceptance** Profile carries a **small frozen** `removeProvisionedAppx` list (pinned catalog ids) so M1 exit proves offline remove + FirstLogon safety net end-to-end. This is explicit acceptance intent, not an auto-on recommended set. Schema default remains empty for other Profiles.
6. **Metal job kinds** — after Wizard (ticket **15**), unless maintainer rescopes; first metal kind = `winget` only; stubs + fail-closed unknown kinds until then.
7. **OS reboot** — Supervisor requests reboot via Win32 when `NeedsReboot`; metal reboot-required matrix folds into the metal-jobs owning card.
8. **Hardware acceptance** — M4; stricter evidence bars only; same Supervisor / settle / jobs (no fork).
9. **Hygiene carries** — Smoke plaintext+wipe until a metal secrets vertical; splash D2D only if S4 FirstPaintBudget fails on real Smoke; Diff VHD / digest-gated ISO rebuild is maintainer opt not a product ticket; `BundleDto`/`SettleDto` → `*File` opportunistic on next BundleLoader touch; AppearanceOnce stays optional bundle field until a Profile appearance story is grilled.

### Consequences

- [ROADMAP](../ROADMAP.md) / [TICKETS](../TICKETS.md) next card = **14** (maintainer Smoke prove-out, including keep-flag assertions for the pinned acceptance ids).
- Do not label Wizard or keep-flag expansion `ready-for-agent` until **14** is green (unless maintainer rescopes).
- Update [samples/acceptance.profile.json](../../samples/acceptance.profile.json) with the pinned remove-list.

### Review trigger

M1 Smoke green on real ISO; or maintainer explicitly rescopes to Wizard-first; or pinned acceptance AppX ids vanish from current Win11 media (re-pin catalog ids).
