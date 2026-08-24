# ADR-011: Alpha defaults may move; guest pwsh runtime may not

**Status:** Accepted · **Date:** 2026-08-06  
**Clarifies:** [ADR-004](ADR-004-stack-and-guest-control-plane.md) (no guest pwsh **runtime** ≠ never spawn `powershell.exe`)

### Context

Grill locks helped ship M1–M3. Some now block simpler paths (batch winget/scoop, catalog-time arch) while exceptions already exist (Scoop bootstrap via inbox `powershell.exe`).

### Rejected

Treating every grill line as invariant. Forbidding inbox `powershell.exe` entirely. One C# spawn per package as identity. Runtime native PE audit as default policy.

### Decision

| Tier | Meaning | Change bar |
|------|---------|------------|
| **Invariant** | Identity / safety | New ADR |
| **Default** | Shipped behaviour | Spike + ADR amendment or issue |
| **Guideline** | Convenience | Issue |

Invariants stay in their ADRs (Source ISO, Supervisor FirstLogon, no guest pwsh product runtime, host `pwsh -File` servicing, residual erase, remove-list, CDM not primary).

**Defaults (alpha-revisable):** package install shape (per-job vs delegated batch); fail-closed scope (**invariants fail-closed, packages best-effort + evidence** unless explicitly strict); architecture truth at catalog time ([ADR-010](ADR-010-arm64-package-policy.md)).

Supervisor remains the orchestrator. It may delegate the package slice to `winget` / `scoop` / `wsl`. Inbox `powershell.exe` is allowed only for Scoop bootstrap or narrow import/configure wrappers.

### Review trigger

Delegated import/configure regresses splash-before-Explorer or makes FirstLogon nondeterministic in Smoke without an explicit harness switch.
