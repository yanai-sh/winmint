# Agentic playbook

**Phase:** Product backlog **01–30** closed ([TICKETS](../TICKETS.md)). Next card: maintainer pick or new issue (grill / to-spec). Lasting locks: [DESIGN](../DESIGN.md#decisions-locked-grill).

**Read:** [DESIGN](../DESIGN.md) · [TICKETS](../TICKETS.md) · [CONTEXT](../../CONTEXT.md) · [TDD](../TDD.md) · [AGENTS](../../AGENTS.md)

## Session rules

One issue per session. Apply `ready-for-agent` only when starting that work; remove it when the issue closes. TDD at the issue’s seam. Keep grill locks intact — do not reopen settled decisions silently.

Before `/implement` or a ticket code review: working tree clean **or** non-ticket WIP committed/stashed. Review `git diff <ticket-base>...HEAD` for that work’s commit(s) only — do not mix imaging/docs drive-bys into the review base.

```
Implement issue #N only. Design: docs/design/...
TDD seam S#. just check. See docs/TICKETS.md (closed index). No drive-bys.
```

## Anti-patterns

v1 `runtime/` copy; peer Splash/JSON mailbox; guest pwsh; script paths in BuildPlan; Profile `if` in kernels; Profile presets-in-JSON; casual schema `v2`; CDM-as-primary; commit unless asked; treating spent research notes or session specs as living status.
