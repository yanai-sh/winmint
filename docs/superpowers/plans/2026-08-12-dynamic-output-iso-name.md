# Plan: Dynamic output ISO filename

**Date:** 2026-08-12  
**Spec:** [2026-08-12-dynamic-output-iso-name-design.md](../specs/2026-08-12-dynamic-output-iso-name-design.md)

## Tasks

1. **Helper** — `OutputIsoNaming` in Orchestrator: `ProfileStem`, `DefaultFileName`, `DefaultPath` (TimeProvider-friendly overload).
2. **Wire defaults** — Cli `--out-iso` omit, Wizard omit, ImageServicing null fallback, PwshElevatedPlanRunner fallback.
3. **Resolve consumers** — Assert-MetalEvidence, Invoke-MetalApply, Invoke-Smoke, primary-gate-wizard, artifact hygiene: evidence `outputIsoPath` → single `winmint_*.iso` → legacy `out.iso`.
4. **Docs** — CONTEXT Output ISO, ADR-012 leaf wording, Justfile/README/`Invoke-PrimaryGate` comments.
5. **Tests** — unit helper; keep FlashGuidance path-agnostic; fixtures may keep legacy paths.
6. **Disk** — rename current Gate B `out.iso` → `winmint_sl7_Release_{builtLocal}.iso`; patch `evidence.json` `outputIsoPath`.
7. **`just check`**
