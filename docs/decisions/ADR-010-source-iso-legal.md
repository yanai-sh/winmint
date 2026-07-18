# ADR-010: Source ISO is legally user-supplied

**Status:** Accepted  
**Date:** 2026-07-18  
**Extends:** [ADR-005](ADR-005-user-iso-truth.md)

### Context

ADR-005 already makes the user-selected ISO the technical source of truth. WinMint v2 grilling reaffirmed a harder constraint: the product must not obtain Windows installation media on the user’s behalf.

### Options considered

| Option | Pros | Cons |
|--------|------|------|
| User always provides official Microsoft ISO | Clear license/distribution boundary | Friction vs “download for me” |
| Bundle / pin / silent-download ISO or UUP | Smoother UX | Legal and distribution risk; product owns Microsoft media |
| Optional helper download with consent | Convenience | Still moves WinMint toward distributing Windows bits |

### Decision

The user **must always provide** an official Microsoft Windows **Source ISO**. WinMint does not bundle, pin, cache-as-product-default, or silently download Windows images (including UUP conversion as a public path). This is a **legal** constraint, not only an engineering preference.

### Consequences

- Bootstrap, CLI, and wizard may only accept a user-supplied path (or equivalent explicit user fetch outside WinMint).
- Acceptance fixtures use a local ISO the maintainer supplies; CI must not fetch Windows media.
- Any future “download helper” requires a new ADR and legal review.

### Review trigger

Microsoft redistribution / evaluation-media policy changes, or counsel approves a different distribution model.
