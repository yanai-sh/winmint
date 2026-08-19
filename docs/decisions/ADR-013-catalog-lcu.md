# ADR-013: Catalog LCU is ImageServicing

**Status:** Accepted  
**Date:** 2026-08-19  
**Related:** [ADR-001](ADR-001-source-iso-legal.md), [IMAGESERVICING](../design/IMAGESERVICING.md), [DESIGN](../DESIGN.md)

### Context

A user-supplied Source ISO can be the current feature train (e.g. 25H2 / `10.0.26200`) and still behind Patch Tuesday. Guest OOBE then spends a long quality-update wait. Microsoft’s documented image-currency path is Catalog packages + DISM `/Add-Package`, not a UUP dump and not a product-owned golden WIM.

### Decision

When staged `install.wim` UBR is behind the latest same-family **Security Update** (B-release) on the Microsoft Update Catalog, ImageServicing downloads the ARM64 combined LCU (and Catalog-listed checkpoint `.msu` files) into `%ProgramData%\WinMint\Servicing\quality-cache\` keyed by KB + arch + SHA-256, then `dism.exe /Add-Package` on **staged** media only.

- Source ISO stays user-supplied. Prepared-media entries stay an unpatched Source-ISO tree.
- Same DISM `Version` family only (`26200` → 25H2, `26100` → 24H2). Unknown family, 26H1, or x64-only Catalog results fail closed.
- Fail closed when the WIM is behind and Catalog, BITS, or DISM cannot complete.
- Skip download and DISM when `packageUbr <= imageUbr`.
- `just check` never hits Catalog. Maintainer live reconcile is `just quality-check`.
- Evidence fields (`lcu.kb`, `lcu.ubrBefore`, `lcu.ubrAfter`, `lcu.sha256`, `lcu.skipped`) are projection, not a control plane.

### Consequences

- The `AddQualityUpdates` opcode is ImageServicing Materialize-owned, not BuildPlan Profile intent.
- Host Apply progress (`apply-status.txt` / DISM percent) is the long wait when the ISO is behind; guest ZDP after NAT remains short and mandatory.
- Quality-cache is not a product golden WIM and is never rewritten in place as Prepared media.
- Revisit if Microsoft stops publishing combined Catalog `.msu` for the current train, or ships an official in-place path to the next feature release.

### Review trigger

Catalog/DISM applicability break on ARM64 25H2; Microsoft redistribution change; a real 26H1 in-place update from 25H2.
