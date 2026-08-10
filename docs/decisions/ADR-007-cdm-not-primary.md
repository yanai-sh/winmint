# ADR-007: CDM is not primary keep-flag control (M1/M2)

**Status:** Accepted  
**Date:** 2026-08-05  
**Ticket:** 27 · **Issue:** [#39](https://github.com/yanai-sh/winmint/issues/39)

### Context

Debloat vertical is **remove-list only** on `winmint.profile/v1` ([ADR-005](ADR-005-keep-flag-matrix.md), [DEBLOAT](../design/DEBLOAT.md)). Consumer/CDM paths are a separate failure mode from offline provisioned-package removal (per-user Store suggestions / ContentDeliveryManager — not the same as still-provisioned registration). Community HKCU `ContentDeliveryManager` DWORD lists are reset-prone and not edition-guaranteed on Pro. Leftover-confidence *product* cleanup is out of this product era.

### Decision

1. **Primary control plane (M1/M2):** offline **ImageServicing** remove (AppX, capabilities, optional features) with **digests** on apply evidence, plus narrow **FirstLogon PackageManager** safety-net when the Profile remove-list is non-empty.
2. **CDM / consumer-features are not primary** — no Supervisor job or Profile field that treats per-user CDM suppression as the main debloat mechanism for M1/M2.
3. **Optional later:** offline HKLM policy stamps (e.g. CloudContent) when Profile explicitly asks and edition semantics are documented — not ticketed in M1/M2.

### Consequences

- Leftover-confidence *product* cleanup stays out; CDM whack-a-mole is not the M1/M2 control plane.
- Smoke / acceptance evidence continues to assert **offline digests** + guest settle/jobs — not CDM registry state.
- Future CDM work requires a new ADR if it becomes primary policy.
