# ADR-007: CDM is not primary keep-flag control (M1/M2)

**Status:** Accepted  
**Date:** 2026-08-05  
**Updated:** 2026-08-11 — HKLM CloudContent **policy** is product-constant FU posture ([ADR-009](ADR-009-product-constant-policies.md)); per-user CDM spray remains non-primary.  
**Ticket:** 27 · **Issue:** [#39](https://github.com/yanai-sh/winmint/issues/39)

### Context

Debloat vertical is **remove-list only** on `winmint.profile/v1` ([ADR-005](ADR-005-keep-flag-matrix.md), [DEBLOAT](../design/DEBLOAT.md)). Consumer/CDM paths are a separate failure mode from offline provisioned-package removal (per-user Store suggestions / ContentDeliveryManager — not the same as still-provisioned registration). Community HKCU `ContentDeliveryManager` DWORD lists are reset-prone and not edition-guaranteed on Pro. Leftover-confidence *product* cleanup is out of this product era.

### Decision

1. **Primary control plane (M1/M2):** offline **ImageServicing** remove (AppX, capabilities, optional features) with **digests** on apply evidence, plus narrow **FirstLogon PackageManager** safety-net when the Profile remove-list is non-empty.
2. **Per-user CDM is not primary** — no Supervisor job or Profile field that treats HKCU `ContentDeliveryManager` DWORD spray as the main debloat mechanism.
3. **HKLM CloudContent / Store AutoDownload policies** are allowed as **product-constant** machine posture for FU-durable quiet (see ADR-009). That is policy stamp, not CDM-as-primary.
4. Making per-user CDM primary still requires a new ADR.

### Consequences

- Leftover-confidence *product* cleanup stays out; CDM whack-a-mole is not the remove-list control plane.
- Smoke / acceptance evidence continues to assert **offline digests** + guest settle/jobs — not HKCU CDM registry state.
- FU survival = Deprovisioned AppX marks + HKLM policies; never a live re-assert agent ([ADR-008](ADR-008-residual-minimization.md)).
