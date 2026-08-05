# ADR-010: ARM64-first package catalog

**Status:** Accepted  
**Date:** 2026-08-05  
**Related:** [BUILDPLAN](../design/BUILDPLAN.md), [spec](../specs/2026-08-05-package-catalog-arm64.md)

### Decision

1. Ship `config/packages.json` (embedded in Orchestrator). Profile stores **install ids**; Wizard chips use **catalog keys**.
2. `BuildPlan.Plan` fail-closed: `packages.catalog.unknown`, `packages.catalog.unsupportedArch` on arm64 (default when unset).
3. Winget jobs on arm64 images carry `--architecture arm64` when catalog supports arm64.
4. WSL `fromFile` for NixOS-WSL (GitHub release → `wsl --install --from-file`).
5. `package.auditNative` after winget on arm64; strict via `--package-audit-strict` / SL7 metal.

Out of scope unchanged: live winget search, guest pwsh, Profile preset names in JSON.
