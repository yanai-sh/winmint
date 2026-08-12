# ADR-003: DMA interop fixed internal region

**Status:** Accepted  
**Date:** 2026-07-18  
**Origin:** WinMint v1 ADR-006 (same decision; renumbered for this repo)  
**Updated:** 2026-08-12 — sticky latch is `DeviceRegion` Ireland (not Nls Geo)

### Context

Windows 11 Setup DMA (Digital Markets Act) interop affects default apps and promotional payloads during install. Microsoft gates EEA/DMA features on the **region chosen during device setup**; that setup region is sticky until the PC is reset. Smoke includes DMA; FirstLogon must restore the user’s **visible** region without clearing the sticky setup region.

### Decision

Unless explicitly disabled in the Profile, Setup latches **Ireland** as the sticky setup region:

- Locales: `en-IE` via `Microsoft-Windows-International-Core` (specialize)
- Sticky key: `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\DeviceRegion` = GeoID **`68`**
- Seed: `HKU\.DEFAULT\Control Panel\International\Geo` `Nation=68` / `Name=IE` (first-cache race)

No EEA country picker. FirstLogon **restores** Profile `dma.settle` visible locale / user GeoID / time zone / location posture **before** jobs. Visible Geo must not be treated as the DMA latch.

Missing or wrong `DeviceRegion` is **repaired then re-verified** in MachineSetup and Shell settle; fail-closed only if verify still fails after repair.

### Consequences

- Orchestrator unattend must stamp `DeviceRegion` + `.DEFAULT` Geo (not `Control\Nls\Geo`).
- Provisioning `IDmaSetupRegion.EnsureIreland()` runs in MachineSetup and after visible settle (and on settle resume skip).
- Smoke evidence must show visible settle **and** `settle.device_region_ok` or `settle.device_region_repaired`.

### Review trigger

Microsoft removes or changes DMA region requirements, or documents a different sticky setup-region store than `DeviceRegion`.
