# Spec: Surface Catalog offline driver injection

**Status:** Published — [#63](https://github.com/yanai-sh/winmint/issues/63) (`ready-for-agent`; grill closed 2026-08-05)  
**Authority:** [CONTEXT](../../CONTEXT.md) · [IMAGESERVICING](../design/IMAGESERVICING.md) · [TDD](../TDD.md) · [V1-LESSONS](../design/V1-LESSONS.md)  
**Harvest:** v1 `Drivers.ps1` behaviour only — not topology ([ARCHITECTURE harvest rule](../ARCHITECTURE.md#v1-harvest-rule))

## Problem Statement

WinMint v2 can build tailored ISOs and complete FirstLogon reliably on Hyper-V, but it cannot yet inject Surface device drivers offline. For a maintainer running WinMint on a **Surface Laptop 7 (ARM64)**, v1 remains necessary because bare-metal installs require **SurfaceCatalog** driver injection (`surface-laptop-7`) before first boot. Hyper-V Smoke cannot substitute for this hardware path.

The maintainer’s retirement bar for v1 is: **Release-lane ISO + SL7-shaped Profile (recommended debloat, Israel DMA settle, metal packages) + proven driver Apply evidence → manual destructive install on SL7.**

Without offline driver injection, SL7 builds depend on post-install Windows Update for critical hardware enablement — an unacceptable regression from v1’s proven SL7 acceptance matrix.

## Solution

Add optional **Surface Catalog driver injection** to the existing **BuildPlan → ImageServicing** pipeline:

1. **Profile** — additive optional `drivers` block on `winmint.profile/v1` selects a catalog device id (initial wiring: `surface-laptop-7` only; full device list ported from v1 catalog JSON).
2. **BuildPlan** — validate device id against the in-repo catalog; emit an `InjectDrivers` servicing opcode with parameter-only payload (no Profile JSON in kernels).
3. **ImageServicing** — new thin elevated kernel downloads the Microsoft Surface driver MSI during Apply (network required), extracts offline-safe INFs (firmware excluded; SurfaceMsiSafe class filter), injects into mounted `install.wim` and setup-critical subset into `boot.wim`, records **driver inventory** in workdir evidence and **digests** on `ImageEvidence`.
4. **Product posture** — stamp `DisableCoInstallers=1` offline (v1 driver hygiene) via existing policy stamping path or bundled with driver vertical.

Absent or empty `drivers` ⇒ no injection (Smoke and minimal Profiles unchanged).

## Proposed testing seams

Confirm before implement:

| Seam | What we test | Why here |
|------|----------------|----------|
| **S1 — BuildPlan** (primary) | Parse/validate `drivers`; unknown `deviceId` fail-closed; `surface-laptop-7` emits `InjectDrivers` in correct stage order (after keep-flag removes, before `StampOfflinePolicies`); no opcode when field absent | Same pattern as keep-flag tickets **11–12**, **19–20** |
| **S2 — ImageServicing Apply** (same ticket) | `RecordingElevatedPlanRunner` receives `InjectDrivers` with `mountDir`, `workDirectory`, `deviceId`, prepared driver source path params; stage order preserved | Prior art: `KeepFlagServicingTests`, `CapabilityPlanTests`, `ImageServicingApplyTests` |
| **Not S4** | No Hyper-V driver prove-out in this ticket | SL7 bare metal is maintainer gate **B** after Apply inventory evidence |

No new seam. Kernel `.inf` classification logic may use fixture-backed self-checks inside the servicing script only if S2 cannot observe outcomes without DISM — prefer digest keys on `ImageEvidence` over private helper tests.

## User Stories

1. As a maintainer building for Surface Laptop 7, I want to declare `surface-laptop-7` in my Profile, so that the output ISO includes offline-safe Surface drivers before I wipe my laptop.
2. As a maintainer, I want the build to download the official Surface driver MSI from Microsoft Download Center during Apply, so that I do not manually fetch and stage driver packages for every rebuild.
3. As a maintainer, I want firmware-class drivers excluded from offline injection, so that I do not brick UEFI/firmware update paths.
4. As a maintainer, I want display/Bluetooth/camera-class drivers deferred to online PnP/WU (SurfaceMsiSafe filter), so that offline injection stays within Microsoft’s safe subset v1 proved on SL7.
5. As a maintainer, I want drivers injected into the mounted Windows image (`install.wim`), so that first boot on bare metal has core Surface hardware support.
6. As a maintainer, I want a setup-critical driver subset injected into `boot.wim`, so that Windows Setup/WinPE can access storage/USB during install from USB media.
7. As a maintainer, I want a `WinMint-DriverInventory.json` (or equivalent) in the Apply workdir listing included vs excluded drivers, so that gate **B** can confirm firmware exclusion before a destructive SL7 install.
8. As a maintainer, I want driver outcomes reflected in `ImageEvidence` digests, so that inventory is machine-readable without opening JSON by hand.
9. As a maintainer, I want unknown or unsupported catalog device ids to fail closed at Plan time, so that a typo does not produce a driverless ISO silently.
10. As a maintainer, I want catalog device ids validated against the image architecture (ARM64 for SL7), so that I cannot inject amd64 drivers into an arm64 WIM.
11. As a maintainer, I want minimum Windows build checked against the catalog entry, so that an too-old Source ISO fails early with a clear error.
12. As a maintainer, I want download URLs restricted to Microsoft hosts, so that driver fetch cannot be redirected to arbitrary URLs via a tampered catalog.
13. As a maintainer, I want MSI administrative extract to time out fail-closed, so that a hung `msiexec` does not block Apply indefinitely.
14. As a maintainer, I want zero offline-safe INFs after classification to fail the build, so that “SurfaceCatalog selected but nothing injected” cannot pass as success.
15. As a maintainer, I want `DisableCoInstallers` stamped offline when drivers are injected, so that vendor companion apps do not ride along with driver install (v1 hygiene).
16. As a maintainer, I want Profiles without a `drivers` block to behave exactly as today, so that Smoke and acceptance Profiles need no change.
17. As a maintainer, I want `samples/sl7.profile.json` updated with the `drivers` block, so that the SL7 template is copy-paste ready for metal builds.
18. As a maintainer, I want driver injection ordered after keep-flag offline removes and before payload staging, so that imaging stages stay consistent with existing ImageServicing invariants.
19. As a maintainer, I want the full v1 Surface device catalog JSON ported into v2, so that future devices do not require a schema bump — only BuildPlan wiring expands later.
20. As a maintainer, I want only `surface-laptop-7` wired in BuildPlan/Wizard initially, so that this ticket stays one session and SL7-focused.
21. As a maintainer running `just check`, I want S1/S2 tests to run without network or DISM, so that daily development stays fast.
22. As a maintainer running real Apply on SL7, I want network access during build for catalog download, so that the built-in SurfaceCatalog path matches v1 behaviour.
23. As a maintainer, I want driver injection to use the existing one-UAC `RunPlan.ps1` loop, so that Apply does not prompt repeatedly.
24. As a maintainer, I want kernels to receive parameters only (no Profile parsing in pwsh), so that ImageServicing architecture invariants hold.
25. As a maintainer retiring v1 for my workflow, I want SL7 ISO builds to combine recommended debloat, Israel DMA settle, metal packages, and Surface drivers in one saved Profile, so that rebuilds are reproducible.
26. As a maintainer, I want local autologon Profiles to remain the metal default, so that FirstLogon Supervisor provisioning runs unattended after install (drivers are independent of account mode).
27. As a maintainer, I want Phone Link removed by the existing recommended debloat preset, so that I do not need a separate Profile flag for Cross Device/Your Phone.
28. As a maintainer, I want Apply failures to preserve the workdir with logs/inventory, so that I can diagnose download, extract, or DISM Add-Driver failures.
29. As a maintainer, I want `PreventDeviceMetadataFromNetwork` (existing product constant) to remain compatible with WU driver delivery post-install, so that offline injection and online deferred drivers coexist.
30. As a maintainer, I want v1’s SL7 hardware acceptance *ideas* (inventory signals, firmware excluded) harvestable without copying v1’s PowerShell monolith, so that v2 stays testable at BuildPlan/ImageServicing seams.

## Implementation Decisions

### Modules

- **BuildPlan** — parse optional `drivers`; validate against ported catalog; emit `InjectDrivers` stage + params; extend `Profile` / wire DTOs additively on `winmint.profile/v1`.
- **ImageServicing** — new `ServicingOpcode.InjectDrivers`; Materialize owns params (`mountDir`, `workDirectory`, `deviceId`, catalog metadata, paths to prepared INF tree); extend `ImageEvidence.Digests` with driver inventory keys.
- **Elevated kernel** — new thin `servicing/Inject-SurfaceDrivers.ps1` (name illustrative): download → MSI extract → classify → DISM Add-Driver (Windows + WinPE subset); write inventory JSON under workdir `logs/`.
- **Catalog** — port v1 `surface-drivers.json` into Orchestrator-owned static data (validated at Plan); only `surface-laptop-7` accepted in Plan until a follow-on expands wiring.

### Profile contract (additive)

```json
"drivers": {
  "source": "surfaceCatalog",
  "deviceId": "surface-laptop-7"
}
```

- `source` — only `"surfaceCatalog"` in this vertical; unknown source ⇒ Plan fail-closed.
- `deviceId` — must exist in catalog; must match mounted image architecture; optional block omitted ⇒ no driver stages.
- No preset names in JSON (same polarity discipline as keep-flag host presets).

### Stage ordering

```
MountInstallWim
→ [RemoveProvisionedAppx?]
→ [RemoveCapabilities?]
→ [DisableOptionalFeatures?]
→ [InjectDrivers?]          ← new
→ StampOfflinePolicies      ← include DisableCoInstallers when drivers injected
→ StagePayload
→ InjectUnattend
→ StampOfflineShell
→ ExportWim
→ BuildIso
```

### v1 behaviour to harvest (not copy)

- SurfaceCatalog download page scrape → MSI URL on `download.microsoft.com`
- Filename regex / minimum build / architecture guardrails
- MSI `/a` administrative install with timeout
- `Copy-WinMintClassifiedDriverPayload` with `SurfaceMsiSafe` strategy (firmware never injected)
- `Invoke-DriverInjection` into install.wim + setup-critical subset into boot.wim
- Inventory object: included count, excluded count, per-INF reasons
- Coinstaller registry stamp (offline machine hive)

### v1 explicitly not ported

- Guest FirstLogon driver logic (none existed)
- `WinMint.ps1` pipeline entry
- Host driver export/mirror paths not needed for SL7 catalog-only vertical
- Custom/OemMsi driver sources (follow-on if ever needed)
- Wizard UI for driver picker (CLI/Profile only in this ticket)

### Greenfield rationale (does not block this vertical)

v2 greenfield addressed **ProvisioningSession** reliability (guest pwsh, Splash peer, JSON mailbox). Driver injection is **host ImageServicing** offline DISM work — deferred in [ADR-006](../decisions/ADR-006-post-keepflag-sequencing.md), not rejected. v2 WIM metadata discipline and thin kernels improve safety vs v1 monolith.

### Confidence gate (maintainer, out of ticket exit)

1. Hyper-V **Release** Smoke green on SL7-shaped Profile (drivers may be present; Smoke SKU remains Pro VM — driver stage runs on Apply but metal driver correctness is not S4-gated).
2. Real Apply on SL7 host produces inventory with firmware excluded and non-zero included offline count.
3. Manual destructive SL7 install — maintainer-timed after gate **B**.

## Testing Decisions

- Test **observable outcomes** through BuildPlan and ImageServicing interfaces only ([TDD](../TDD.md)).
- **S1:** invalid/unknown `deviceId`; valid SL7 emits opcode in order; absent `drivers` unchanged plan; architecture mismatch fails at Plan when detectable from run context.
- **S2:** `RecordingElevatedPlanRunner` captures `InjectDrivers` params; digests include driver keys when runner simulates success; failure preserves workdir (existing Apply pattern).
- Use **spec literals** (`surface-laptop-7`, opcode names, digest key prefixes) — not full inventory snapshots tied to a live MSI version.
- Prior art: `KeepFlagPlanTests`, `KeepFlagServicingTests`, `CapabilityPlanTests`, `ImageServicingApplyTests`.
- **No** network/DISM in `just check`. Optional maintainer script to dry-run catalog resolution against live Microsoft pages — harness-only, not CI.
- **No** S4 extension for driver signals in this ticket.

## Out of Scope

- Hyper-V or automated proof of driver correctness on SL7 hardware (maintainer manual install).
- Wizard driver picker UI.
- Non-SurfaceCatalog sources (`Custom`, `SurfaceMsiSafe` manual MSI path, host driver export).
- Wiring catalog device ids beyond validation (only `surface-laptop-7` executes end-to-end initially).
- v1 BuildProfile migration or dual-read.
- Post-install live driver audit product (v1 `liveInstallAudit`).
- BitLocker, enterprise driver silos, DPAPI.
- Changing account mode (`MicrosoftOobe` remains never in product).
- Keep-flag / Phone Link changes (recommended preset already removes Your Phone).
- Developer baseline, restore point, bootstrap release path.

## Further Notes

- **samples/sl7.profile.json** should gain the `drivers` block when implementing; aligns with maintainer Israel DMA + recommended debloat + metal packages template.
- v1 reference: [`winmint_v1` Drivers.ps1](https://github.com/yanai-sh/winmint_v1/blob/main/src/runtime/image/Private/Image/Drivers.ps1), [`surface-drivers.json`](https://github.com/yanai-sh/winmint_v1/blob/main/config/surface-drivers.json), [Hardware-Acceptance.md](https://github.com/yanai-sh/winmint_v1/blob/main/docs/Hardware-Acceptance.md) SL7 section.
- After ship: maintainer pick to run gate **B** on physical SL7; close v1 for this workflow when satisfied.
- Follow-on (not this ticket): Wizard field, additional wired device ids, optional local MSI path for air-gapped builds.
