# ADR-010: ARM64-first package catalog

**Status:** Accepted · **Date:** 2026-08-05 · **Updated:** 2026-08-11

### Context

A catalog that is x64-first will plan installs that fail or emulate on this product’s ARM64 images.

### Rejected

Live winget search in Wizard. Runtime PE audit as default FirstLogon policy. Third-party `scoop-aarch64` as a silent catalog dependency. `winget show` / a manifest URL alone as architecture proof.

### Decision

`config/packages.json` is the human catalog. Profile stores **install ids**; Wizard chips are **catalog keys** (UI vocabulary, never JSON).

Plan fail-closes on unknown id or unsupported arch (arm64 when unset).

Architecture truth is **catalog time**: `just packages-check` writes a hashed receipt; `just check` validates it offline. Stubs skipped. Optional metal `package.auditNative` is not default product policy ([ADR-011](ADR-011-alpha-posture-and-package-delegation.md)).

Supervisor may delegate the package phase (import/batch) per ADR-011. Derived import JSON is generated, not a second source of truth.

### Review trigger

Winget/scoop lose a durable ARM64 prove path, or the product adds a second arch as first-class.
