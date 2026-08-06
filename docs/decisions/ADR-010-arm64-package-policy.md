# ADR-010: ARM64-first package catalog

**Status:** Accepted (amended 2026-08-06)  
**Date:** 2026-08-05  
**Related:** [BUILDPLAN](../design/BUILDPLAN.md), [spec](../specs/2026-08-05-package-catalog-arm64.md), [ADR-011](ADR-011-alpha-posture-and-package-delegation.md)

### Decision

1. Ship `config/packages.json` (embedded in Orchestrator). Profile stores **install ids**; Wizard chips use **catalog keys**.
2. `BuildPlan.Plan` fail-closed: `packages.catalog.unknown`, `packages.catalog.unsupportedArch` on arm64 (default when unset).
3. Winget jobs on arm64 images carry `--architecture arm64` when catalog supports arm64 (or equivalent in generated import JSON).
4. WSL `fromFile` for NixOS-WSL (GitHub release → `wsl --install --from-file`).
5. **Architecture truth at catalog time:** maintainer verifies winget/scoop manifests when editing `packages.json` (CI validator preferred). **`package.auditNative`** is optional metal/regression evidence — not default FirstLogon policy ([ADR-011](ADR-011-alpha-posture-and-package-delegation.md)).
6. Scoop: prefer official **main** / **extras** manifests with `architecture.arm64`; optional catalog field **`scoopBucket`**. Do **not** depend on third-party `scoop-aarch64` for catalog entries unless explicitly grilled.

Out of scope unchanged: live winget search in Wizard, guest pwsh product runtime, Profile preset names in JSON.

### Amended (2026-08-06)

Plan may emit derived **`winget import`** JSON (or configure YAML after spike) from the catalog. Supervisor may delegate the winget/scoop package phase per [ADR-011](ADR-011-alpha-posture-and-package-delegation.md).
