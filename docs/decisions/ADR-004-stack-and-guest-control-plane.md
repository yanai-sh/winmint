# ADR-004: Product stack and guest control plane

**Status:** Accepted  
**Date:** 2026-07-27  
**Updated:** 2026-08-06 — package delegation and guest PowerShell nuance ([ADR-011](ADR-011-alpha-posture-and-package-delegation.md))  
**Revises:** [ADR-002](ADR-002-v2-architecture.md)  
**Companion:** [STACK.md](../STACK.md), [ARCHITECTURE.md](../ARCHITECTURE.md), [CONTEXT.md](../../CONTEXT.md)

### Context

Guest/runtime reliability (Shell-before-Explorer, DMA settle races, splash timing) dominates real Smoke pain. Host Profile typing alone does not fix that. A hybrid PowerShell FirstLogon control plane reintroduces pwsh cold start on the critical path. Precedent from v1 or earlier v2 drafts is not authority when a simpler design wins.

### Decision

1. **Product languages:** C# for CLI, Orchestrator, and **guest FirstLogon/Machine setup orchestration**. PowerShell 7.6+ for **host Servicing kernels only**. No Rust/Go/C++/Python/Node in product runtime. No **guest pwsh product runtime** or v1 script monolith; inbox **`powershell.exe`** for Scoop bootstrap or delegated winget import/configure is allowed ([ADR-011](ADR-011-alpha-posture-and-package-delegation.md)).
2. **Host:** Unelevated C# Orchestrator/CLI (**BuildPlan**); elevated thin `pwsh -File` Servicing (**ImageServicing** adapters). No wrapping v1 `WinMint.ps1`.
3. **One guest AOT binary (Provisioning Supervisor):** Winlogon Shell after auth; `--machine-setup` from SetupComplete.cmd for stamp-only Machine setup. Deep module **ProvisioningSession** — one phase machine; modes are entrypoints. In-process Direct2D/GDI splash (no peer Splash.exe).
4. **Shell registration:** Servicing stamps Shell offline; Machine setup fail-closed verifies/restamps (same posture as autologon stamp).
5. **DMA settle:** Final snapshot after bounded restore. Hard: locale, GeoID, time zone. Soft: location posture. **Same policy** on Hyper-V Smoke and bare metal.
6. **Provisioning jobs:** Supervisor orchestrates phases; winget/Scoop/wsl run as child processes or **delegated batch** (import/configure + batch scoop). Smoke vs metal differ in job *set*, not necessarily one-spawn-per-id ([ADR-011](ADR-011-alpha-posture-and-package-delegation.md)).
7. **Status:** In-memory for paint; JSON snapshots for evidence only (projections — not a control-plane mailbox).
8. **Fail-open:** Unlock Shell on `complete`/`failed` (+ failed dwell) and wall-clock timeout; hold Shell on `reboot` with durable checkpoint resume.
9. **Theme:** Splash-owned canvas; no Profile appearance / theme apply until a Profile appearance story is grilled — no theme hard-gate.
10. **Provisioning lock:** Shell tenure while Supervisor is Shell; hard input lockdown is later hardening.
11. **NuGet:** Microsoft-thin (source-gen JSON, `System.CommandLine`, xUnit; Avalonia 12.1.x for host wizard). Every package needs “why not BCL.”
    - **Wizard-only:** `CommunityToolkit.Mvvm` — Microsoft source-gen `INotifyPropertyChanged` / commands; Avalonia’s documented MVVM path. Why not BCL: avoids hand-rolled INPC boilerplate across multi-step ViewModels. **Not on the ISO** (host Wizard only; Wizard stays non-AOT).
12. **Rejected for day-one:** guest **pwsh product runtime**, file-as-control-plane status, C#-only in-process DISM as default, separate Splash.exe peer, Hyper-V-only settle/executor forks, Servicing port with a single adapter, copying v1 `runtime/` topology. *(Not rejected: inbox powershell.exe for Scoop bootstrap or winget import/configure wrappers.)*

### Consequences

- Smoke tickets deepen ProvisioningSession (machine-setup + Shell) over harvesting PreLock.ps1 / agent modules as session entrypoints.
- v1 harvest notes map behaviour into BuildPlan / ProvisioningSession interfaces; scripts are archaeology ([ARCHITECTURE harvest rule](../ARCHITECTURE.md#v1-harvest-rule)).
- Host build wall-clock remains DISM-bound; keep image-quality lanes and VM harness caching.
- Ticket 10 should expose one acceptance interface, not a peer forest of harness entrypoints.
- Wizard Phase A (2026-08-05): multi-step Avalonia host; Phase B (same day): Review Build → ImageServicing.Apply via elevated pwsh.

### Review trigger

Supervisor AOT cold start still loses to Explorer flash; or host `servicing/` becomes a second monolith justifying a C#-only DISM ADR; or a measured job proves C# child-process glue worse than a narrow script exception (then ADR a single helper — not a guest pwsh runtime).
