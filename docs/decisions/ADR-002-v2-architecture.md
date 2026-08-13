# ADR-002: Greenfield architecture and Smoke-first delivery

**Status:** Accepted  
**Date:** 2026-07-18  
**Updated:** 2026-07-28 — deep modules accepted; Design Acceptance signed; lanes `Test`|`Release`; Cli→Orchestrator reserved  

### Context

WinMint v2 is a new repository with no v1 contract back-compat. Empirical pain is guest/runtime reliability. Prefer elegant modern solutions over prior intent when they conflict. Smoke and bare metal should share product standards (settle, executor, reboot, lock) when possible. Early scaffold must not recreate v1’s shallow multi-process FirstLogon (peer Splash + JSON mailbox) or ambient engine script forest.

### Decision

1. **Orchestrator-first:** typed C# (`net11.0`, rolling .NET 11 preview SDK) owns Profile validation, planning, and the public **C# CLI**; unelevated by default. Deep module: **BuildPlan**.
2. **Elevated PowerShell** runs thin **host Servicing** kernels only — not guest FirstLogon, not a v1 `WinMint.ps1` subprocess. Deep module: **ImageServicing** (port type only when a second adapter needs it).
3. **Clean-sheet JSON contracts** — no migration target for v1 BuildProfile / InstallPlan.
4. **Dual hosts:** Avalonia Wizard on the **build host**; ISO guest UI is the Supervisor splash — not Avalonia. Front ends enter through HostCompile (not BuildPlan directly). Living: [BUILDPLAN](../design/BUILDPLAN.md).
5. **Guest control plane (ADR-004):** one Native AOT Provisioning Supervisor (`--machine-setup` + Winlogon Shell); deep module **ProvisioningSession**; DMA settle; C# provisioning jobs; in-memory status + evidence snapshots; Shell-tenure lock; checkpoint reboot.
6. **First vertical = Smoke:** Profile → ISO → Hyper-V unattend → FirstLogon with splash + DMA hard-field evidence ([ADR-003](ADR-003-dma-interop.md)); plumbing only; password-required local account; Hyper-V smoke SKU = Pro.
7. **CLI + Wizard** both host HostCompile; Smoke path proved first historically.
8. **Issues are the work surface** ([issue-tracker](../agents/issue-tracker.md)); no PR ceremony unless asked.
9. **Image quality lanes** (run override, not Profile): public names **`Test`** (Smoke/fast) and **`Release`** (hard recompress + WinSxS cleanup). See [ARCHITECTURE.md](../ARCHITECTURE.md#image-quality-run-override-not-profile).
10. **v1 harvest:** invariants and evidence ideas only — not `runtime/` topology, peer Splash, or file control planes ([ARCHITECTURE harvest rule](../ARCHITECTURE.md#v1-harvest-rule)).
11. **No tactical DDD packing** as day-one structure — one pipeline; deepen the three modules rather than pre-splitting projects.

### Consequences

- Debloat / Wizard / metal jobs shipped; BitLocker and hard input lockdown remain issue-scoped.
- Do not expect C# orchestration to shorten DISM-bound ISO builds.
- Do not reintroduce guest pwsh product runtime or peer Splash.exe as Shell.
- Do not invent Servicing ports before a second adapter exists.

### Review trigger

Smoke Hyper-V gate fails to converge; net11 GA forces TFM/SDK policy change; or ADR-004 review triggers fire.
