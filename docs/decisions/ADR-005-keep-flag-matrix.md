# ADR-005: Debloat is a remove-list

**Status:** Accepted · **Date:** 2026-08-03

Living name is **Debloat**. “Keep-flag” in older text is the same decision.

### Context

Live uninstallers (BCU) suggested declarative lists but only work online. Offline DISM can remove provisioned AppX / capabilities / features. FirstLogon “rehydrate” is usually still-provisioned registration or consumer/CDM — not a reason to invert polarity.

### Rejected

Keep-list polarity, Profile preset names in JSON, shipping BCU, UI Automation uninstall, leftover-confidence product cleanup, CDM as primary ([ADR-007](ADR-007-cdm-not-primary.md)), Ent/Edu RemoveDefault on Pro Smoke.

Host preset **`recommended`** expanding to ids is allowed — the JSON still contains ids, never the preset name. Empty lists stay empty; Plan does not silently fill them.

### Decision

Nothing is removed unless the Profile lists it. Catalogs in-repo are the legal ids; Plan fail-closes on unknown. ImageServicing is the offline primary; FirstLogon AppX safety-net is optional when the list is non-empty.

Capabilities/features use the same polarity. Concrete catalogs and opcodes live in code.

### Review trigger

Microsoft changes offline remove semantics; Pro gains a supported RemoveDefault equivalent; maintainer overturns remove-list polarity.
