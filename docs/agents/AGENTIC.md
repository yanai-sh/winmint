# Agentic playbook

**Phase:** **Alpha** ([TICKETS](../TICKETS.md)). Next card: maintainer pick or new issue (grill / to-spec). Requirement tiers: [ADR-011](../decisions/ADR-011-alpha-posture-and-package-delegation.md) · [DESIGN grill index](../DESIGN.md#grill-index-tiered).

**Read:** [DESIGN](../DESIGN.md) · [TICKETS](../TICKETS.md) · [CONTEXT](../../CONTEXT.md) · [TDD](../TDD.md) · [AGENTS](../../AGENTS.md)

## Session rules

One issue per session. Apply `ready-for-agent` only when starting that work; remove it when the issue closes. TDD at the issue’s seam. **Invariants** stay fixed; **defaults** revisable per ADR-011 — do not treat grill rows as immutable law.

Before `/implement` or a ticket code review: working tree clean **or** non-ticket WIP committed/stashed. Review `git diff <ticket-base>...HEAD` for that work’s commit(s) only — do not mix imaging/docs drive-bys into the review base.

```
Implement issue #N only. Design: docs/design/...
TDD seam S#. just check. See docs/TICKETS.md (closed index). No drive-bys.
```

## Anti-patterns

v1 `runtime/` copy; peer Splash/JSON mailbox; **guest pwsh product runtime**; script paths in BuildPlan; Profile `if` in kernels; Profile presets-in-JSON; casual schema `v2`; CDM-as-primary; commit unless asked; treating spent research notes or session specs as living status.
