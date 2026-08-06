# WinMint — Agent contract

Windows 11 ISO builder (**alpha**). **ARM64-first**. Host Servicing: **pwsh 7.6+**. Guest FirstLogon: **Provisioning Supervisor** (C# phase machine); package installs may delegate to platform tools ([ADR-011](docs/decisions/ADR-011-alpha-posture-and-package-delegation.md)).

## Phase: alpha (post backlog 01–30)

Product `/implement` is **maintainer pick** or a new GitHub issue (grill → to-spec) — **one issue per session**. Apply `ready-for-agent` only when starting that work. Closed index: [TICKETS](docs/TICKETS.md). Requirement tiers: [ADR-011](docs/decisions/ADR-011-alpha-posture-and-package-delegation.md); grill index: [DESIGN](docs/DESIGN.md#decisions-locked-grill).

Gate/locks: [ROADMAP](docs/ROADMAP.md#design-acceptance) · [DESIGN](docs/DESIGN.md#decisions-locked-grill)  
Closed index: [TICKETS](docs/TICKETS.md) · Sessions: [AGENTIC](docs/agents/AGENTIC.md) · Seams: [TDD](docs/TDD.md)

[`CONTEXT`](CONTEXT.md) · [`DESIGN`](docs/DESIGN.md) · [`ARCHITECTURE`](docs/ARCHITECTURE.md) · [`ROADMAP`](docs/ROADMAP.md) · [`Smoke`](docs/specs/2026-07-27-smoke.md) · [`design/`](docs/design/)

## Core rule

**CLI/Orchestrator creates intent. Servicing mutates the offline image. Provisioning Supervisor finishes live-user setup.**

Elevate **only** Servicing `pwsh -File`. No v1 `WinMint.ps1`. No guest **pwsh product runtime** — inbox `powershell.exe` for Scoop bootstrap or delegated winget import/configure is OK ([ADR-011](docs/decisions/ADR-011-alpha-posture-and-package-delegation.md)).

## Deep modules

| Module | Design |
|--------|--------|
| BuildPlan | [BUILDPLAN](docs/design/BUILDPLAN.md) |
| ImageServicing | [IMAGESERVICING](docs/design/IMAGESERVICING.md) |
| ProvisioningSession | [PROVISIONINGSESSION](docs/design/PROVISIONINGSESSION.md) |

## Smoke stance

Local+autoLogon only; Pro Hyper-V; DMA on for acceptance Profile; `Test`|`Release`; `%ProgramData%\WinMint\`.

## README

Lobby, not brochure — concise real content only; no placeholders. No badges yet: none has live metadata to mirror (at first release ≤5 functional, linked, non-vanity). Grows: quickstart · features at smoke pass · screenshots via dark/light `<picture>` block · CONTRIBUTING + CODE_OF_CONDUCT before public launch. Bundled third-party assets → `THIRD_PARTY_NOTICES.md`, not the README.

## While implementing

One issue/session. Keep `just check` green. Sequencing in [ADR-006](docs/decisions/ADR-006-post-keepflag-sequencing.md) is **met**. **Invariants:** remove-list only; no Profile presets-in-JSON; product-default **`recommended`** host expansion (issue 56); no casual `v2`; CDM not primary ([ADR-007](docs/decisions/ADR-007-cdm-not-primary.md)); residual self-erase ([ADR-008](docs/decisions/ADR-008-residual-minimization.md)). **Defaults** (package shape, fail-closed scope, audit) revisable per [ADR-011](docs/decisions/ADR-011-alpha-posture-and-package-delegation.md).

```powershell
just check
```

Commits when asked: `docs:` · `feat(scope):` · `fix(scope):` …

## Solo maintainer — no PRs

This is a **solo** project. **Do not open pull requests** unless the maintainer explicitly asks. Default delivery: branch → commit → push when asked → maintainer merges locally (or fast-forward `dev`/`main`). Issues remain the work surface; PRs are not triage or review theater ([issue-tracker](docs/agents/issue-tracker.md)).
