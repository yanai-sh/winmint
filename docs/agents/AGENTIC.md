# Agentic playbook

**Hold:** [TICKETS](../TICKETS.md) — no product `/implement` while active.

**Read:** [DESIGN](../DESIGN.md) · [TICKETS](../TICKETS.md) · [CONTEXT](../../CONTEXT.md) · [TDD](../TDD.md)

## On hold

| Do | Don’t |
|----|-------|
| Doc quality / backlog edits | Feature types, Servicing kernels |
| Splash spike (throwaway, `.scratch/`) | Product splash code |
| Keep grill locks intact | Reopen settled decisions silently |
| `just check` if touching scaffold | File `ready-for-agent` for 01–10 |

## After hold lifts

One ticket from TICKETS per session. TDD at that seam. Ticket **04+** need splash spike first. After M1 green: `/to-spec` for M2+.

Before `/implement` or a ticket code review: working tree clean **or** non-ticket WIP committed/stashed. Review `git diff <ticket-base>...HEAD` for that ticket’s commit(s) only — do not mix imaging/docs drive-bys into the review base.

```
Implement Smoke ticket 0N only. Design: docs/design/...
TDD seam S#. just check. See docs/TICKETS.md. No drive-bys.
```

## Anti-patterns

v1 `runtime/` copy; peer Splash/JSON mailbox; guest pwsh; script paths in BuildPlan; Profile `if` in kernels; starting 04 before spike; implementing under hold; commit unless asked.
