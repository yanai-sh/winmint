# ADR-005: Keep-flag matrix (provisioned AppX remove-list)

**Status:** Accepted  
**Date:** 2026-08-03  
**Wayfinder:** [Keep-flag matrix wayfinding](https://github.com/yanai-sh/winmint/issues/13)

### Context

Debloat / keep-flag is a post-M1 vertical ([TICKETS](../TICKETS.md), [ADR-002](ADR-002-v2-architecture.md)). Bulk Crap Uninstaller research ([note](../research/2026-08-03-bulk-crap-uninstaller.md)) suggested declarative lists and multi-source catalogs, but BCU is live-only and must not ship. Offline DISM and AppX rehydrate research ([offline DISM](../research/2026-08-03-offline-dism-remove-apis.md), [rehydrate](../research/2026-08-03-appx-rehydrate-after-oobe.md)) define the Microsoft surfaces and ownership split.

### Decision

1. **Remove-list only** — nothing removed unless the Profile lists it. No keep-list polarity; no BCU include/exclude filters in Profile.
2. **No Profile presets** — named presets are a host/Wizard concern that expand to the same remove-list.
3. **First vertical kinds = provisioned AppX only** — capabilities and optional features deferred.
4. **Static in-repo catalog** — legal package-family identities for the remove-list. Plan validates ⊆ catalog; ImageServicing inventories the mount and records evidence. Discovery does not invent the catalog.
5. **Extend `winmint.profile/v1`** with an optional remove-list (default empty). No `v2` bump for this vertical.
6. **Ownership:** ImageServicing is primary (offline `Remove-AppxProvisionedPackage` / DISM `/Image`, plus `Deprovisioned` stamps when update-survival is required). ProvisioningSession is a narrow FirstLogon safety net (`PackageManager.RemovePackageAsync`; live deprovision only if still provisioned).
7. **Out of this vertical:** shipping BCU; UI Automation uninstall; leftover confidence cleanup; CDM whack-a-mole as primary policy; Ent/Edu-only RemoveDefault on Pro smoke.

### Consequences

- Design module: [KEEPFLAG](../design/KEEPFLAG.md). AppX vertical implemented (**11–13**). Expansion sequencing: [ADR-006](ADR-006-post-keepflag-sequencing.md).
- BuildPlan gains catalog validation + servicing stage params for removes; ImageServicing gains a remove opcode; ProvisioningSession may gain an optional safety-net job — not a second debloat brain.

### Review trigger

Maintainer Smoke green (ticket **14**) before Wizard / keep-flag expansion; or Microsoft changes provisioned-AppX offline remove semantics; or Pro gains a supported RemoveDefault-equivalent policy.
