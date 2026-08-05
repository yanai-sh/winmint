# ADR-005: Keep-flag matrix (provisioned AppX remove-list)

**Status:** Accepted (partially superseded for kinds — see below)  
**Date:** 2026-08-03  
**Wayfinder:** [Keep-flag matrix wayfinding](https://github.com/yanai-sh/winmint/issues/13)

### Context

Debloat / keep-flag is a post-M1 vertical ([TICKETS](../TICKETS.md) closed index, [ADR-002](ADR-002-v2-architecture.md)). BCU (live uninstaller) suggested declarative lists and multi-source catalogs but is live-only and must not ship. Microsoft offline surfaces are DISM `/Image` removes for provisioned AppX, capabilities, and optional features; FirstLogon “rehydrate” is usually still-provisioned registration or consumer/CDM installs — ownership split below (see [KEEPFLAG](../design/KEEPFLAG.md)).

### Decision

1. **Remove-list only** — nothing removed unless the Profile lists it. No keep-list polarity; no BCU include/exclude filters in Profile.
2. **No Profile presets** — named presets are a host/Wizard concern that expand to the same remove-list(s). Product zero-config default is host preset **`recommended`** (issue 56); Acceptance remains prove-out-only.
3. **First vertical kinds = provisioned AppX** — shipped tickets **11–13**. Capabilities / optional features were deferred here, then sequenced in [ADR-006](ADR-006-post-keepflag-sequencing.md) and implemented tickets **19–20** (same remove-list polarity + catalogs).
4. **Static in-repo catalog(s)** — legal identities for each remove-list kind. Plan validates ⊆ catalog; ImageServicing inventories the mount and records evidence. Discovery does not invent the catalog.
5. **Extend `winmint.profile/v1`** with optional remove-list fields (default empty). No `v2` bump for this vertical.
6. **Ownership:** ImageServicing is primary (offline DISM `/Image` removes / disables, plus `Deprovisioned` stamps when update-survival is required for AppX). ProvisioningSession is a narrow FirstLogon safety net for AppX (`PackageManager.RemovePackageAsync`; live deprovision only if still provisioned).
7. **Out of this vertical:** shipping BCU; UI Automation uninstall; product leftover-confidence cleanup; CDM as primary policy ([ADR-007](ADR-007-cdm-not-primary.md)); Ent/Edu-only RemoveDefault on Pro smoke. **Superseded 2026-08-05 (issue 56):** product-default curated **`recommended`** host expansion is in — still remove-list polarity, still no silent BuildPlan fill of intentional empty lists, still no Profile preset names.

### Consequences

- Design module: [KEEPFLAG](../design/KEEPFLAG.md). AppX **11–13**; capabilities/features **19–20**. Sequencing history: [ADR-006](ADR-006-post-keepflag-sequencing.md).
- BuildPlan validates catalogs + emits servicing stage params; ImageServicing runs remove/disable opcodes; ProvisioningSession optional AppX safety-net — not a second debloat brain.

### Supersession

- **§3 “capabilities deferred”** — superseded by implementation **19–20** (fields still remove-list + catalog; no recommended set). Policy §§1–2, 4–7 remain binding.
- Review trigger for maintainer Smoke before expansion — **met** (ticket **14**).

### Review trigger

Microsoft changes provisioned-AppX / capability / feature offline remove semantics; or Pro gains a supported RemoveDefault-equivalent policy; or maintainer overturns remove-list / no-recommended-set polarity.
