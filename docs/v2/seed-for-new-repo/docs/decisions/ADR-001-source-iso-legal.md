# ADR-001: Source ISO is legally user-supplied

**Status:** Accepted  
**Date:** 2026-07-18

### Context

WinMint could pin a golden image, download UUP payloads, or otherwise obtain Windows media for the user. That creates license and distribution risk.

### Decision

The user **must always provide** an official Microsoft Windows **Source ISO**. WinMint does not bundle, pin, cache-as-product-default, or silently download Windows images (including UUP as a public product path). This is a **legal** constraint, not only an engineering preference.

### Consequences

- CLI and wizard only accept a user-supplied path (or equivalent explicit user fetch outside WinMint).
- Acceptance fixtures use a local ISO the maintainer supplies; CI must not fetch Windows media.
- Any future download helper requires a new ADR and legal review.

### Review trigger

Microsoft redistribution policy changes, or counsel approves a different model.
