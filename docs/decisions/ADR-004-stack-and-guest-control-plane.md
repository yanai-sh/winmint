# ADR-004: Guest control plane

**Status:** Accepted · **Date:** 2026-07-27 · **Updated:** 2026-08-06 · **Revises:** [ADR-002](ADR-002-v2-architecture.md)

### Context

Host Profile typing does not fix Shell-before-Explorer, splash timing, or DMA settle races. A PowerShell FirstLogon control plane puts pwsh cold start on that path.

### Rejected

Guest pwsh **product runtime**, file-as-control-plane status, peer Splash.exe, in-process DISM as default, Hyper-V-only settle/executor forks, a Servicing port with one adapter, copying v1 `runtime/`.

Not rejected: inbox `powershell.exe` for Scoop bootstrap or narrow winget import/configure ([ADR-011](ADR-011-alpha-posture-and-package-delegation.md)).

### Decision

- C# orchestrates CLI, planning, and **guest** FirstLogon / Machine setup. PowerShell 7.6+ is **host Servicing kernels only**.
- One AOT **Provisioning Supervisor**: Winlogon Shell after auth; `--machine-setup` from SetupComplete. In-process splash. Modes are entrypoints of one phase machine.
- Servicing stamps Shell offline; Machine setup fail-closed verifies/restamps.
- Status is in-memory for paint; JSON is evidence only.
- Fail-open unlock on complete/failed/timeout; hold Shell on reboot with a durable checkpoint.
- NuGet is Microsoft-thin; every package needs “why not BCL.” Wizard-only MVVM toolkit stays off the ISO.

DMA latch: [ADR-003](ADR-003-dma-interop.md). Package delegation: ADR-011.

### Review trigger

Supervisor AOT still loses to Explorer flash; `servicing/` becomes a second monolith; or a measured job proves C# child-process glue worse than one script helper (ADR that helper — not a guest pwsh runtime).
