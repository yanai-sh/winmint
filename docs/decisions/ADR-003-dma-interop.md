# ADR-003: DMA interop fixed internal region

**Status:** Accepted  
**Date:** 2026-07-18  
**Origin:** WinMint v1 ADR-006 (same decision; renumbered for this repo)  
**Updated:** 2026-08-12 — sticky latch is `DeviceRegion` Ireland (not Nls Geo)  
**Updated:** 2026-08-16 — OOBE answers are not the latch. Ireland `International-Core` lives in **oobeSystem**; specialize is DeviceRegion + `.DEFAULT` Geo only.

### Context

Windows 11 Setup DMA (Digital Markets Act) interop affects default apps and promotional payloads during install. Microsoft gates EEA/DMA features on the **region chosen during device setup**; that setup region is sticky until the PC is reset. Smoke includes DMA; FirstLogon must restore the user’s **visible** region without clearing the sticky setup region.

OOBE still shows “Hi there” if `International-Core` is only in specialize. That component is **OOBE answers** (hide the region/language pane). The DMA latch is `DeviceRegion`, not that pane. DMA enabled must not gate whether OOBE is answered.

### Decision

Unless explicitly disabled in the Profile, Setup latches **Ireland** as the sticky setup region:

- Sticky key: `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\DeviceRegion` = GeoID **`68`** (specialize `reg add`)
- Seed: `HKU\.DEFAULT\Control Panel\International\Geo` `Nation=68` / `Name=IE` (specialize; first-cache race)
- Ireland locales: `en-IE` via `Microsoft-Windows-International-Core` in **oobeSystem** (Input/System/User). `UILanguage` / `UILanguageFallback` stay the Source ISO pack (`en-US` on the English ISO); `en-IE` is not an installed MUI. Specialize does **not** emit `International-Core`.

When DMA is disabled, oobeSystem still answers `International-Core` from `dma.settle` locale (same `UILanguage` rule). Time zone in Shell-Setup is always `dma.settle`, including while DMA-on locales are Ireland.

No EEA country picker. FirstLogon **restores** Profile `dma.settle` visible locale / user GeoID / time zone / location posture **before** jobs. Visible Geo must not be treated as the DMA latch.

Missing or wrong `DeviceRegion` is **repaired then re-verified** in MachineSetup and Shell settle. MachineSetup must **not** fail-closed on `UnauthorizedAccessException` / `SecurityException` (OOBE still holds the key during SetupComplete; non-zero exit reseals `IMAGE_STATE_COMPLETE` → Recovery and kills unattended S4). Shell settle remains fail-closed if verify still fails after repair.

### Consequences

- Orchestrator unattend stamps `DeviceRegion` + `.DEFAULT` Geo in specialize (not `Control\Nls\Geo`, not specialize `International-Core`).
- OOBE answers (`International-Core` in oobeSystem) always emit; Ireland locales only when DMA is enabled.
- Provisioning `IDmaSetupRegion.EnsureIreland()` runs in MachineSetup and after visible settle (and on settle resume skip).
- Smoke evidence must show visible settle **and** `settle.deviceRegionOk` or `settle.deviceRegionRepaired`.

### Review trigger

Microsoft removes or changes DMA region requirements, or documents a different sticky setup-region store than `DeviceRegion`.
