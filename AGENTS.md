# WinMint — Agent contract

Windows 11 ISO builder (greenfield v2). **ARM64-first**. Host Servicing: **pwsh 7.6+**. Guest FirstLogon: **C# only**.

## Phase: implementation Released

Product `/implement` may proceed from [TICKETS](docs/TICKETS.md) — **one ticket per session**. Apply `ready-for-agent` only when starting that ticket. Next open card: **none** (deferred: WSL / Wizard polish / ExitWindowsEx — [ADR-006](docs/decisions/ADR-006-post-keepflag-sequencing.md)).

Gate/locks: [ROADMAP](docs/ROADMAP.md#design-acceptance) · [DESIGN](docs/DESIGN.md#decisions-locked-grill)  
Backlog: [TICKETS](docs/TICKETS.md) · Sessions: [AGENTIC](docs/agents/AGENTIC.md) · Seams: [TDD](docs/TDD.md)

[`CONTEXT`](CONTEXT.md) · [`DESIGN`](docs/DESIGN.md) · [`ARCHITECTURE`](docs/ARCHITECTURE.md) · [`ROADMAP`](docs/ROADMAP.md) · [`Smoke`](docs/specs/2026-07-27-smoke.md) · [`design/`](docs/design/)

## Core rule

**CLI/Orchestrator creates intent. Servicing mutates the offline image. Provisioning Supervisor finishes live-user setup.**

Elevate **only** Servicing `pwsh -File`. No v1 `WinMint.ps1`. No guest pwsh.

## Deep modules

| Module | Design |
|--------|--------|
| BuildPlan | [BUILDPLAN](docs/design/BUILDPLAN.md) |
| ImageServicing | [IMAGESERVICING](docs/design/IMAGESERVICING.md) |
| ProvisioningSession | [PROVISIONINGSESSION](docs/design/PROVISIONINGSESSION.md) |

## Smoke stance

Local+autoLogon only; Pro Hyper-V; DMA on for acceptance Profile; `Test`|`Release`; `%ProgramData%\WinMint\`.

## README

Lobby, not brochure — concise real content only; no placeholders. No badges yet: none has live metadata to mirror (at first release ≤5 functional, linked, non-vanity). Grows: quickstart at ticket **01** · features at smoke pass · screenshots via dark/light `<picture>` block · CONTRIBUTING + CODE_OF_CONDUCT before public launch. Bundled third-party assets → `THIRD_PARTY_NOTICES.md`, not the README.

## While implementing

One ticket/session from [TICKETS](docs/TICKETS.md). Keep `just check` green. Sequencing: [ADR-006](docs/decisions/ADR-006-post-keepflag-sequencing.md) — metal (**17** reboot, **18** Scoop) before keep-flag capabilities (**19** spike → **20** implement).

```powershell
just check
```

Commits when asked: `docs:` · `feat(scope):` · `fix(scope):` …
