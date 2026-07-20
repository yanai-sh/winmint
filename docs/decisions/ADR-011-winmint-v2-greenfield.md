# ADR-011: WinMint v2 greenfield rewrite

**Status:** Accepted  
**Date:** 2026-07-18  
**Supersedes (for the v2 project only):** [ADR-001](ADR-001-gpui-to-webview2-wizard.md) WebView2 wizard; [ADR-008](ADR-008-profile-schema-v4.md) as the v2 profile contract  
**Revises (for the v2 project only):** [ADR-002](ADR-002-dual-setup-shell-hosts.md) (keep dual-host *shape*, Avalonia wizard + Native AOT splash); [ADR-003](ADR-003-powershell-engine-boundary.md) (C# Orchestrator + elevated PS Servicing/Payload)  
**Does not change:** this repository’s v1 code until cutover; [ADR-005](ADR-005-user-iso-truth.md) / [ADR-010](ADR-010-source-iso-legal.md); [ADR-006](ADR-006-dma-interop.md) intent for smoke

### Context

v1 works but is constrained by PowerShell monolith orchestration, WebView2 wizard hosting, and InstallPlan-shaped staged contracts. v2 is a **new clean GitHub repository** (not an in-place rewrite), with **no backwards compatibility** to v1 profiles or CLI.

### Decision

1. **New repo**, pre-planned commit history; this repo remains v1 until bootstrap/docs cut over.
2. **Orchestrator-first:** typed C# (`net11.0` preview, SDK pinned) owns Profile validation, planning, CLI; unelevated by default.
3. **Elevated PowerShell** runs thin Servicing kernels (DISM/WIM/hive/export) and ISO **Payload** only — not `WinMint.ps1` as a subprocess.
4. **C# CLI** is the only product headless surface (tiny download bootstrap script OK).
5. **Clean-sheet JSON contracts** — no v1 BuildProfile/InstallPlan migration target.
6. **Dual hosts:** Avalonia wizard (later vertical) + separate **Native AOT** splash (Direct2D/GDI-class); not Avalonia splash for smoke.
7. **First vertical = Smoke:** Profile → ISO → Hyper-V unattend install → FirstLogon complete with splash + **DMA** restore evidence; plumbing only (no debloat/keep matrix, no BitLocker policy); password-required local account; Hyper-V smoke SKU = **Pro** (product default SKU may remain Home later).
8. **CLI-first Smoke** — Avalonia wizard after the ISO→FirstLogon path is green.
9. **Hybrid Payload:** port-and-reshape DMA restore, provisioning lock, thin transaction, Common, splash host model (OOBE stages / a11y / Autologon stamp-before-toolchain); clean-sheet staged contracts + thin agent stub; drop InstallPlan module catalog / SetupComplete debloat matrix from the smoke path.
10. **Image quality lanes** (carry forward v1 semantics): test/Smoke builds optimize for speed (soft/no WIM recompress, skip `StartComponentCleanup`); release builds optimize for smaller ISO (`Max` + cleanup). Run override, not Profile. Manifest/report must record what ran. ISO fingerprint cache, checkpoint, and push-only remain VM harness concerns.

### Consequences

- v1 ADRs still govern this repo until cutover; agents must not treat ADR-011 as a license to rewrite v1 in place.
- Copy-ready docs for the new repo: [`docs/v2/seed-for-new-repo/`](../v2/seed-for-new-repo/).
- Next planning step in the **new** repo: `/setup-matt-pocock-skills` → `/to-spec` (Smoke) → `/to-tickets` → `/implement`. Skip `/wayfinder` unless the Smoke spec is blocked by fog.
- Greenfield C# does not by itself shorten DISM-bound ISO builds; keep the two quality lanes.

### Review trigger

Smoke Hyper-V gate fails to converge; or legal/SDK (net11 GA) forces TFM change.
