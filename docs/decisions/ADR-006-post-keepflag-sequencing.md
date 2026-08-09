# ADR-006: Post–keep-flag sequencing (spent)

> **Spent.** Living rules: [DESIGN](../DESIGN.md). Do not treat this file as session law.

**Status:** Accepted (sequencing complete) · **Date:** 2026-08-04

Ordered M1 Smoke → Wizard → metal jobs → caps/features. That order is **done** (git history).

## Lasting policy (still true)

- Remove-list only; no Profile preset names in JSON
- Product-default host preset **`recommended`** expands → ids
- Stay on `winmint.profile/v1` until a real breaking change
- CDM not primary
- Wizard is a BuildPlan host, not a second planner
- Acceptance Profile may pin a small frozen remove-list for prove-out

Deferred UX/hardening (Appearance, full D2D, DPAPI channel, rename campaigns) are **issue-scoped** — not living vetoes. See [DESIGN](../DESIGN.md).
