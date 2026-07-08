# ADR-005: User-provided ISO as source of truth

**Status:** Accepted  
**Date:** 2026-07-07

### Context

WinMint services official Microsoft Windows 11 ISOs. The product could pin a golden image or download UUP payloads.

### Decision

The **user-selected source ISO** is the only Windows version DISM services. No bundled Microsoft payloads; no public UUP Dump conversion path. Document minimum version (25H2+) in README.

### Consequences

- AppX/removal catalogs are best-effort against common SKUs.
- Users with odd OEM bundles may need follow-up outside WinMint.

### Review trigger

None unless Microsoft distribution policy changes.
