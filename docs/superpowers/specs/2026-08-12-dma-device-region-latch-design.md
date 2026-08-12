# Spec: DMA DeviceRegion latch (hardened)

**Date:** 2026-08-12  
**Authority:** [ADR-003](../../decisions/ADR-003-dma-interop.md) · [BUILDPLAN](../../design/BUILDPLAN.md) · [PROVISIONINGSESSION](../../design/PROVISIONINGSESSION.md) · Microsoft DMA setup-region rule (Insider blog) · GeoID table (Learn)

## Problem

WinMint latches DMA via specialize `en-IE` plus `HKLM\...\Control\Nls\Geo\Nation`. That Nls path is not the sticky setup-region store Windows uses for Digital Markets Act interop. The sticky key is `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\DeviceRegion` (`DeviceRegion` DWORD = GeoID). After FirstLogon settle restores a non-EEA visible Geo (e.g. Israel `117`), a missing `DeviceRegion` can cache from `GetUserGeoID` and permanently miss EEA/DMA posture.

## Goal

When `dma.enabled`:

1. Setup region is Ireland (`GeoID 68` / ISO `IE`) and **sticky**.
2. Visible locale / user Geo / TZ / location come only from `dma.settle`.
3. Missing or wrong `DeviceRegion` is **repaired then re-checked**; fail-closed only if repair will not stick.
4. Smoke evidence proves setup region Ireland, not only visible settle.

## Decision (locked)

- Fail posture: repair-then-verify (not warn-and-continue).
- Owners: specialize stamp + MachineSetup `EnsureIreland` + Shell settle `EnsureIreland` after visible restore.
- Stamp surface: `DeviceRegion` + seed `HKU\.DEFAULT\Control Panel\International\Geo` (`Nation=68`, `Name=IE`); **remove** dead `Control\Nls\Geo` write.
- Approach: dual-phase latch + settle gate (not ImageServicing hive edits).

## Architecture

```text
BuildPlan specialize
  → International-Core en-IE (unchanged)
  → RunSynchronous: DeviceRegion=68 + .DEFAULT Geo Nation/Name
  → no Control\Nls\Geo

MachineSetup (dma.on)
  → IDmaSetupRegion.EnsureIreland()  // fail MachineSetup if verify fails

Shell settle (dma.on)
  → Apply visible dma.settle (unchanged)
  → poll + final snapshot hard locale/Geo/TZ (unchanged)
  → soft location warn (unchanged)
  → EnsureIreland() after hard fields OK
  → fail-closed only if DeviceRegion still ≠ 68
```

Invariant: `SetUserGeoID(settle.geoId)` never replaces the DMA latch. `DeviceRegion` is the latch.

## Components

| Piece | Module | Behavior |
|-------|--------|----------|
| `DmaInterop` constants | Contracts | `IrelandLocale=en-IE`, `IrelandGeoId=68`, `IrelandGeoName=IE` — single source |
| Specialize XML | BuildPlan | Real registry stamps; drop Nls path |
| `IDmaSetupRegion` | Provisioning | `ReadDeviceRegion()`, `EnsureIreland()` → `AlreadyOk` \| `Repaired`; throw/fail if post-write verify ≠ 68 |
| `Win32DmaSetupRegion` | Provisioning | HKLM `DeviceRegion` DWORD; seed `.DEFAULT` Geo |
| `SessionEnvironment.DmaSetup` | Provisioning | Production always wired; tests fake |
| Smoke assert | `tools/vm` | Require setup-region evidence phase when DMA on |

## Status / evidence

| Code | When |
|------|------|
| `machineSetup.dma_setup_region_failed` | MachineSetup EnsureIreland verify failed |
| `settle.device_region_repaired` | Settle repaired DeviceRegion then verified |
| `settle.device_region_ok` | Settle found DeviceRegion already 68 |
| `settle.device_region_failed` | Settle repair/verify failed (hard) |

`settle.ok` / `settle.location_warn` still mean visible hard fields OK; setup-region phases are additional when DMA on. Smoke requires one of `settle.device_region_ok` \| `settle.device_region_repaired` (or resume path that already proved prior settle including setup region).

When `dma.enabled` and `DmaSetup` port is null → fail-closed (port required).

## Errors

- Visible hard mismatch → existing `settle.hard_mismatch` (jobs skipped).
- Setup region verify fail → `settle.device_region_failed` (jobs skipped); unlock fail-open unchanged.
- MachineSetup setup-region fail → `Failed` before Shell tenure.

## Testing (TDD seams)

- **S1** `BuildPlan.Plan`: unattend contains `DeviceRegion` `/d 68`, `.DEFAULT` Geo, `en-IE`; does **not** contain `Control\Nls\Geo`.
- **S3** MachineSetup: DMA on + broken DeviceRegion → repair succeeds; repair that won’t stick → `machineSetup.dma_setup_region_failed`.
- **S3** Shell settle: after visible match, DeviceRegion wrong → repair → `settle.device_region_repaired` + Complete; irreparable → `settle.device_region_failed`, no jobs.
- **S4** smoke assert: setup-region phase required with DMA hard fields.

Expected literals from this spec / Learn Geo table: `68`, `IE`, `en-IE`.

## Docs

- Update ADR-003 consequences: sticky latch = `DeviceRegion` Ireland; settle restores visible only; repair-then-verify.
- Touch BUILDPLAN / PROVISIONINGSESSION / CONTEXT one-liners for setup vs visible region.

## Out of scope

- Profile schema bump
- Changing settle visible targets
- ImageServicing offline hive edits
- Writing `IntegratedServicesRegionPolicySet.json`
- UCPD bypass theater beyond normal HKLM admin write during specialize / MachineSetup / elevated Shell

## Success

- Fresh DMA-on install: Settings “Device setup region” = Ireland after Israel (or other) visible settle
- `just check` green with new S1/S3 tests
- Smoke fails if setup-region evidence missing
