# ADR-010: ARM64-first package catalog

**Status:** Accepted (amended 2026-08-11)  
**Date:** 2026-08-05  
**Related:** [BUILDPLAN](../design/BUILDPLAN.md), [spec](../specs/2026-08-05-package-catalog-arm64.md), [ADR-011](ADR-011-alpha-posture-and-package-delegation.md)

### Decision

1. Ship `config/packages.json` (embedded in Orchestrator). Profile stores **install ids**; Wizard chips use **catalog keys**.
2. `BuildPlan.Plan` fail-closed: `packages.catalog.unknown`, `packages.catalog.unsupportedArch` on arm64 (default when unset).
3. Winget jobs on arm64 images carry `--architecture arm64` when catalog supports arm64 (or equivalent in generated import JSON).
4. WSL `fromFile` for NixOS-WSL (GitHub release → `wsl --install --from-file`).
5. **Architecture truth at catalog time:** `just packages-check` (`tools/host/Invoke-PackagesCheck.ps1`) proves live winget ids with `winget download` (App Installer has no `install --dry-run`) and scoop ids via manifest + archive download, then writes `config/packages.proof.json`. `just check` validates that receipt offline (content-hash). Stubs (`stub: true`) are skipped. **`package.auditNative`** remains optional metal evidence — not default FirstLogon policy ([ADR-011](ADR-011-alpha-posture-and-package-delegation.md)).
6. Scoop: prefer official **main** / **extras** manifests with `architecture.arm64`; optional catalog field **`scoopBucket`**. Do **not** depend on third-party `scoop-aarch64` for catalog entries unless explicitly grilled.

Out of scope unchanged: live winget search in Wizard, guest pwsh product runtime, Profile preset names in JSON.

### Amended (2026-08-06)

Plan may emit derived **`winget import`** JSON (or configure YAML after spike) from the catalog. Supervisor may delegate the winget/scoop package phase per [ADR-011](ADR-011-alpha-posture-and-package-delegation.md).

### Amended (2026-08-11)

Catalog-time truth is download prove + committed `packages.proof.json` receipt gate (see [packages proof design](../superpowers/specs/2026-08-11-packages-proof-design.md)), not `winget show` / manifest URL alone.
