# Agentic playbook

Living rules: [DESIGN](../DESIGN.md). Glossary: [CONTEXT](../../CONTEXT.md). Contract: [AGENTS](../../AGENTS.md).

## Hot path

1. CONTEXT → DESIGN  
2. The one module design for the seam you touch  
3. ARCHITECTURE / STACK only when shape or pins matter  
4. Cold: `decisions/`, `specs/`, `research/` — not status. Shipped specs are historical. Active plans only under `superpowers/` for in-flight work.

Prefer module names BuildPlan / ImageServicing / ProvisioningSession over “engine.”

## ADR conflicts

DESIGN wins. Say so if an ADR disagrees; don’t silently override either without saying it.

## Anti-patterns

v1 `runtime/` copy; peer Splash/JSON mailbox; guest pwsh product runtime; script paths in BuildPlan; Profile `if` in kernels; presets-in-JSON; CDM-as-primary; treating research as living status; committing unless asked.
