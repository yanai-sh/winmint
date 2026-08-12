# WinMint — Agent contract

Windows 11 ISO builder (**alpha**). **ARM64-first**. Host Servicing: **pwsh 7.6+**. Guest FirstLogon: **Provisioning Supervisor**; packages may delegate to platform tools.

## Core rule

**CLI/Orchestrator creates intent. Servicing mutates the offline image. Provisioning Supervisor finishes live-user setup.**

Elevate **only** Servicing `pwsh -File`. No v1 `WinMint.ps1`. No guest **pwsh product runtime** — inbox `powershell.exe` for Scoop bootstrap or narrow winget import/configure is OK.

## Invariants

Living list: [DESIGN](docs/DESIGN.md#invariants). Short form: Source ISO · Supervisor FirstLogon · remove-list / no presets-in-JSON / CDM not primary · residual erase · single-image WIM · `winmint.profile/v1` until a real break.

## Defaults

Revisable with spike evidence — [DESIGN](docs/DESIGN.md#defaults).

## Deep modules

BuildPlan · ImageServicing · ProvisioningSession — [docs/design/](docs/design/).

## Session

Prefer one issue per session. Tiny same-risk fixes in touched code are fine — do not leave obvious breakage to obey “no drive-bys.” Apply `ready-for-agent` when starting scoped implement work. Keep `just check` green. Commits when asked: `docs:` · `feat(scope):` · `fix(scope):` …

```powershell
just check
```

**Solo — no PRs** unless asked. Issues are the work surface ([issue-tracker](docs/agents/issue-tracker.md)).

## Read order

[CONTEXT](CONTEXT.md) → [DESIGN](docs/DESIGN.md) → module design for the seam → [AGENTIC](docs/agents/AGENTIC.md) when needed · [TDD](docs/TDD.md) · [ARCHITECTURE](docs/ARCHITECTURE.md) · [STACK](docs/STACK.md)
