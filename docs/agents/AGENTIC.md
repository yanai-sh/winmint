# Agentic playbook

**Phase:** Implementation **Released** — product backlog **01–30** done ([TICKETS](../TICKETS.md)). Next card: maintainer pick or new tickets (grill / to-spec). Lasting locks: [DESIGN](../DESIGN.md#decisions-locked-grill).

**Read:** [DESIGN](../DESIGN.md) · [TICKETS](../TICKETS.md) · [CONTEXT](../../CONTEXT.md) · [TDD](../TDD.md) · [AGENTS](../../AGENTS.md)

## Session rules

One ticket per session. Apply `ready-for-agent` only when starting that ticket; remove it when the ticket closes. TDD at the ticket’s seam. Keep grill locks intact — do not reopen settled decisions silently.

Before `/implement` or a ticket code review: working tree clean **or** non-ticket WIP committed/stashed. Review `git diff <ticket-base>...HEAD` for that ticket’s commit(s) only — do not mix imaging/docs drive-bys into the review base.

```
Implement ticket NN only. Design: docs/design/...
TDD seam S#. just check. See docs/TICKETS.md. No drive-bys.
```

## Anti-patterns

v1 `runtime/` copy; peer Splash/JSON mailbox; guest pwsh; script paths in BuildPlan; Profile `if` in kernels; Profile presets-in-JSON; product-default recommended remove-list; casual schema `v2`; CDM-as-primary; commit unless asked.
