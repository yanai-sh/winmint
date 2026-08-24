# ADR-003: DMA latch is Ireland DeviceRegion

**Status:** Accepted · **Date:** 2026-07-18 · **Updated:** 2026-08-16

DMA here is the EU Digital Markets Act, not device memory.

### Context

Setup DMA features follow the **region chosen during device setup**. That setup region is sticky until reset. FirstLogon must restore the user’s **visible** region without clearing the latch. “Hi there” is a different problem (OOBE answers).

### Rejected

- Nls Geo as the latch
- `International-Core` in specialize as the latch (that component hides the OOBE pane; it is not DeviceRegion)
- Gating OOBE answers on DMA enabled
- Fail-closed Machine setup on UnauthorizedAccess while OOBE still holds the key (exit 1 reseals to Recovery; Smoke cannot drive that)
- Treating a sticky intermediate settle failure as the result — final snapshot wins
- EEA country picker

### Decision

Unless the Profile disables DMA, Setup latches **Ireland** (`DeviceRegion` GeoID 68). Specialize stamps DeviceRegion + `.DEFAULT` Geo only. Ireland `International-Core` lives in **oobeSystem**. `UILanguage` stays the Source ISO pack.

OOBE answers always emit. FirstLogon restores Profile `dma.settle` visible locale/Geo/TZ **before** jobs. Visible Geo is not the latch.

Wrong DeviceRegion: repair then re-verify. Machine setup does not fail-closed on access denied during SetupComplete. Shell settle still fail-closes if verify fails after repair.

Hive paths and unattend shape live in code.

### Review trigger

Microsoft changes DMA region requirements or documents a different sticky store than `DeviceRegion`.
