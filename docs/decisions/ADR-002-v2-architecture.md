# ADR-002: Greenfield architecture

**Status:** Accepted · **Date:** 2026-07-18 · **Updated:** 2026-08-23

### Context

v2 has no v1 contract. Pain is guest FirstLogon reliability, not host typing. Scaffold must not recreate v1’s peer Splash + JSON mailbox + guest pwsh forest.

### Rejected

v1 `runtime/` topology, peer Splash.exe, file mailbox as control plane, guest pwsh product runtime, wrapping `WinMint.ps1`, in-place commit of multi-edition `install.wim`, caller `--reuse-media`, day-one DDD project splits, Clean Architecture / MediatR as backbone.

v1 harvest is **ideas only** (password-required local, DMA Ireland, lanes, Pro Smoke, fail-open unlock). Sibling `winmint_v1` is archaeology.

### Decision

- **BuildPlan** (unelevated C#): Profile → plan artifacts. Front ends enter through **HostCompile**, not BuildPlan directly.
- **ImageServicing** (elevated `pwsh -File` kernels): apply that plan to a user Source ISO. Port type only when a second adapter exists.
- **ProvisioningSession** (one AOT Supervisor): Machine setup or Shell tenure. Detail: [ADR-004](ADR-004-stack-and-guest-control-plane.md).
- Lanes `Test` | `Release` are a **run override**, not a Profile field.
- **Single-image WIM:** one image; Name/Arch/Edition are identity; UBR may rise after quality updates and is not identity.
- **Prepared media:** ImageServicing-owned immutable Source ISO tree; copy to staged media each Apply; one Apply per host.

Issues are the work surface ([AGENTS.md](../../AGENTS.md#session)).

### Review trigger

Smoke fails to converge; net11 GA forces TFM/SDK policy; or ADR-004 triggers fire.
