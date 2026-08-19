# ADR-001: Source ISO is legally user-supplied

**Status:** Accepted  
**Date:** 2026-07-18

### Context

WinMint could pin a golden image, download UUP payloads, or otherwise obtain Windows media for the user. That creates license and distribution risk.

### Decision

The user **must always provide** an official Microsoft Windows **Source ISO**. WinMint does not bundle, pin, cache-as-product-default, or silently download Windows **images** (including UUP dump as a public product path). This is a **legal** constraint, not only an engineering preference.

Same-train **Microsoft Update Catalog quality `.msu`** (combined SSU+LCU for the staged WIM’s DISM `Version` family, e.g. `10.0.26200`) is **not** a Source ISO. That fetch is in-product ImageServicing — [ADR-013](ADR-013-catalog-lcu.md). CI must still not fetch ISOs.

### Consequences

- CLI and wizard only accept a user-supplied Source ISO path (or equivalent explicit user fetch outside WinMint).
- Acceptance fixtures use a local ISO the maintainer supplies; CI must not fetch Windows media.
- Catalog quality packages for the same feature train are allowed under ADR-013. Feature-upgrade media (25H2 → 26H1) and UUP dump remain out.

### Review trigger

Microsoft redistribution policy changes, or counsel approves a different model.
