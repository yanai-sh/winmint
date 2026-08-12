# Plan: DMA DeviceRegion latch (hardened)

**Spec:** [2026-08-12-dma-device-region-latch-design.md](../specs/2026-08-12-dma-device-region-latch-design.md)

## Vertical slices

1. **S1** — `DmaInterop` constants; specialize XML DeviceRegion + `.DEFAULT` Geo; drop Nls; update BuildPlan tests
2. **S3 port** — `IDmaSetupRegion` + `SessionEnvironment.DmaSetup`; fakes default OK
3. **S3 MachineSetup** — EnsureIreland when DMA on; fail `machineSetup.dma_setup_region_failed`
4. **S3 settle** — after hard visible match, EnsureIreland; repaired/ok/failed phases
5. **Win32** — `Win32DmaSetupRegion`; wire `Program.CreateEnvironment`
6. **Smoke + docs** — Assert-SmokeEvidence setup-region phases; ADR-003 / BUILDPLAN / PROVISIONINGSESSION / CONTEXT

Each slice: failing test → minimal code → next. End with `just check`.
