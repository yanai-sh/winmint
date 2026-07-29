# WinMint — Agent contract

Windows 11 ISO builder (greenfield v2). **ARM64-first**. Host Servicing: **pwsh 7.6+**. Guest FirstLogon: **C# only**.

## Phase: pre-implement hold

Product `/implement` is **on hold** until [TICKETS](docs/TICKETS.md) releases it.

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

## While on hold

Docs/quality only. Keep `just check` green if touching scaffold. **No** feature types.

When hold lifts: one ticket/session from [TICKETS](docs/TICKETS.md), starting at **01**.

```powershell
just check
```

Commits when asked: `docs:` on hold; later `feat(scope):` …
