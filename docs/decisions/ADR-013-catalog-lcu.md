# ADR-013: Catalog LCU is ImageServicing

**Status:** Accepted · **Date:** 2026-08-19

### Context

A current-train Source ISO can still be behind Patch Tuesday. Guest OOBE then waits on quality updates. Microsoft’s documented image-currency path is Catalog packages + DISM `/Add-Package`, not UUP dump and not a product-owned golden WIM.

### Rejected

Treating Catalog `.msu` as a Source ISO ([ADR-001](ADR-001-source-iso-legal.md)). Rewriting Prepared media in place. Pinning a KB or Patch Tuesday date. Preview CU as “latest.” Cross-train packages. UUP dump. First file in a DownloadDialog or quality-cache folder as identity. A checkpoint `.msu` standing in for the combined LCU. `just check` hitting Catalog.

### Decision

When staged `install.wim` UBR is behind the newest same-family Catalog **Security Update** (B-release), ImageServicing fetches the ARM64 combined LCU (plus listed checkpoint packages) into a host quality-cache keyed by KB + arch + SHA, then `/Add-Package` on **staged** media only.

Same DISM Version family only. Fail closed if behind and Catalog/BITS/DISM cannot finish. Payload hosts and leaf-KB identity live in code; other hosts and wrong leaves are a miss.

Quality-cache is not Prepared media and not a golden WIM. Skip when already current.

### Review trigger

Microsoft stops publishing combined Catalog `.msu` for the train, ships an official in-place feature-upgrade path, or moves `.msu` bytes off the allowed CDNs.
