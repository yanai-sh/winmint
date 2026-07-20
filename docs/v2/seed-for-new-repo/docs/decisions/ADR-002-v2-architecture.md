# ADR-002: Greenfield architecture and Smoke-first delivery

**Status:** Accepted  
**Date:** 2026-07-18

### Context

WinMint v2 is a new repository. It must avoid v1’s PowerShell orchestration monolith, WebView2 wizard dependency, and InstallPlan-shaped staged contracts, without requiring back-compat.

### Decision

1. **Orchestrator-first:** typed C# (`net11.0` preview, SDK pinned) owns Profile validation, planning, and the public **C# CLI**; unelevated by default.
2. **Elevated PowerShell** runs thin **Servicing** kernels and stages **Payload** — not a port of the v1 `WinMint.ps1` monolith as one subprocess.
3. **Clean-sheet JSON contracts** — no migration target for v1 BuildProfile / InstallPlan.
4. **Dual hosts:** Avalonia wizard (later vertical) + separate **Native AOT** splash; not Avalonia on the ISO for Smoke.
5. **First vertical = Smoke:** Profile → ISO → Hyper-V unattend → FirstLogon with splash + DMA restore evidence ([ADR-003](ADR-003-dma-interop.md)); plumbing only; password-required local account; Hyper-V smoke SKU = Pro.
6. **CLI-first Smoke** — wizard after the path is green.
7. **Hybrid Payload:** port DMA restore, provisioning lock, thin transaction, Common, splash host model (OOBE stages, accessibility, Autologon stamp-before-toolchain); clean-sheet staged contracts + thin agent stub.
8. **Pre-planned git history** via `/to-spec` → `/to-tickets` → `/implement` (see [WORKFLOW.md](../WORKFLOW.md)).
9. **Image quality lanes** (run override, not Profile): test/Smoke prioritizes build speed (soft/no WIM recompress, skip WinSxS component cleanup); release prioritizes smaller ISO (`Max` + cleanup). Record both in the build report. VM ISO cache / checkpoint / push-only are harness concerns. See [ARCHITECTURE.md](../ARCHITECTURE.md#image-quality-run-override-not-profile).

### Consequences

- Debloat, BitLocker policy, Avalonia, and hardware acceptance are later verticals.
- Agents follow WORKFLOW.md; skip wayfinder unless the Smoke spec is blocked by fog.
- Do not expect C# orchestration alone to shorten DISM-bound ISO builds; use the fast lane for iteration.

### Review trigger

Smoke Hyper-V gate fails to converge; or net11 GA forces a TFM policy change.
