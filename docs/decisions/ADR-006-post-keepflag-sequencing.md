# ADR-006: Post–keep-flag sequencing (M1 Smoke before M2)

**Status:** Accepted (sequencing complete 2026-08-05 — lasting policy below)  
**Date:** 2026-08-04  
**Grill:** post-M1 decisions (2026-08-04) — [DESIGN](../DESIGN.md#decisions-locked-grill)

### Context

Tickets **01–13** (M1 Smoke stack + keep-flag AppX vertical) were implemented. Competing next steps at grill time: expand keep-flag (capabilities, presets, auto recommended set), open Wizard (M2), or metal job kinds (winget). This ADR ordered that work.

### Decision (as grilled)

1. **M1 exit first** — one maintainer `just smoke` green on a real Source ISO before Wizard or keep-flag expansion. Fixture-only S4 (`Category=S4`) does not count as M1 exit. **Met** (ticket **14**, 2026-08-04).
2. **Thin tickets (14+)** — no mega-epic; fold carry/ponytail into owning cards.
3. **Wizard after M1 green** — second BuildPlan host only; UI may expand presets → remove-list(s); Profile remains the expanded list ([ADR-005](ADR-005-keep-flag-matrix.md)). **Met** (**15**, packages **22**, polish **25**).
4. **Keep-flag expansion** — capabilities/features after metal milestone (**18**); then **19** spike → **20** offline. **Schema `v2`, Profile presets-in-JSON, and product-default / opt-out “recommended remove set” stay out** until an explicit rescope. Leftover-confidence product cleanup stays out; spike **26** + [ADR-007](ADR-007-cdm-not-primary.md) closed the CDM-as-primary question (not primary).
5. **Acceptance remove-list (grill B4)** — Smoke **acceptance** Profile carries a **small frozen** remove-list (AppX; later also thin capability/feature pins) so prove-out exercises offline remove + digests. Explicit acceptance intent, not an auto-on recommended set. Schema default elsewhere remains empty.
6. **Metal job kinds** — after Wizard (**15**); first = `winget` (**16**), then reboot-resume (**17**), Scoop (**18** metal exit), WSL (**23**). Unknown kinds fail closed until ticketed.
7. **OS reboot** — Supervisor `ISystemReboot` on `NeedsReboot` (`ExitWindowsEx` + `shutdown.exe` fallback — **24**); Profile `*NeedsReboot` subsets on metal package lists.
8. **Hardware acceptance** — M4; stricter evidence bars only (**30** optional `-HardwareM4` / `WINMINT_M4=1`); same Supervisor / settle / jobs (no fork). Full metal-on-hardware campaign still maintainer-timed.
9. **Hygiene carries** — Smoke plaintext + wipe (**28** best-effort overwrite); full DPAPI host→guest channel later; splash status text on GDI (**29**); full D2D only if S4 FirstPaintBudget still fails; Diff VHD / digest-gated ISO rebuild is maintainer opt; `BundleDto`/`SettleDto` → `*File` opportunistic; AppearanceOnce optional until a Profile appearance story is grilled.

### Consequences (current)

- Sequencing **14–30** complete (see [TICKETS](../TICKETS.md)). Next product work is maintainer pick or new tickets — not the deferred queue in this ADR’s original Consequences block.
- **Lasting policy from this ADR + ADR-005/007:** remove-list only; no Profile preset names; no product-default recommended set; stay on `winmint.profile/v1` until a breaking change; CDM not primary; Wizard is not a second planner.
- Acceptance Profile keeps pinned remove-lists ([samples/acceptance.profile.json](../../samples/acceptance.profile.json)).

### Review trigger

Maintainer rescopes lasting policy; or pinned acceptance ids vanish from current Win11 media (re-pin catalog ids); or FirstPaintBudget fails on real Smoke (revisit full D2D).
