# ADR-001: Source ISO is user-supplied

**Status:** Accepted · **Date:** 2026-07-18

### Context

Pinning a golden image or silently fetching Windows media (ISO/UUP) is a license and distribution risk.

### Rejected

Golden ISO, UUP dump as a product path, CI fetching Windows media, treating Catalog `.msu` as a Source ISO.

### Decision

The operator always provides an official Microsoft **Source ISO**. WinMint does not bundle, pin, or download Windows **images**.

Same-train Catalog quality `.msu` is ImageServicing, not a Source ISO ([ADR-013](ADR-013-catalog-lcu.md)). Feature-upgrade media (25H2 → 26H1) stays out.

CI must not fetch ISOs. Maintainer path text lives in `tests/fixtures/maintainer-host.json` — never the bytes.

### Review trigger

Microsoft redistribution policy changes, or counsel approves a different model.
