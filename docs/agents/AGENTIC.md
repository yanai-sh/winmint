# Agentic playbook

Living rules: [DESIGN](../DESIGN.md). Glossary: [CONTEXT](../../CONTEXT.md). Contract: [AGENTS](../../AGENTS.md).

## Hot path

1. CONTEXT → DESIGN  
2. The one module design for the seam you touch  
3. ARCHITECTURE / STACK only when shape or pins matter  
4. Cold: `decisions/`, `specs/`, `research/` — not status

Prefer module names BuildPlan / ImageServicing / ProvisioningSession over “engine.”

## Session

Prefer one issue. Adjacent one-line fixes in code you already touch are OK. Do not refuse a clear bugfix because it was not pre-labeled.

TDD at a module interface (see [TDD](../TDD.md)). Invariants bind; defaults move with spike evidence. Spent ticket sequencing is not law.

Before a focused review: prefer a clean tree or stash unrelated WIP. Review that work’s commits — not the whole branch noise.

## ADR conflicts

DESIGN wins. Say so if an ADR disagrees; don’t silently override either without saying it.

## Anti-patterns

v1 `runtime/` copy; peer Splash/JSON mailbox; guest pwsh product runtime; script paths in BuildPlan; Profile `if` in kernels; presets-in-JSON; CDM-as-primary; treating research as living status; committing unless asked.
