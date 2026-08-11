# Spec: Package catalog + ARM64 harvest

**Status:** Accepted (2026-08-05)  
**Authority:** [ADR-010](../decisions/ADR-010-arm64-package-policy.md)

## Catalog (`config/packages.json`)

- **Catalog key** — Wizard chip id (`zen-browser`).
- **Install id** — Profile `packages.winget` / `scoop` value (`Zen-Team.Zen-Browser`).

## Plan

- Validate all package ids against catalog; arm64 image rejects entries without `arm64` in `architectures`.
- Winget: `--architecture arm64` or generated import JSON with override args. WSL: `wslInstallKind` + fromFile for NixOS-WSL.
- Package phase may be **per-job** (current) or **delegated batch** (import/configure + batch scoop) — Plan generates derived artifacts from catalog ([ADR-011](../decisions/ADR-011-alpha-posture-and-package-delegation.md)).
- Curated packages: **best-effort + evidence** by default; strict fail-closed for metal/CI when flagged.

## Guest

- Winget: `--architecture arm64` when job field set (or import batch).
- WSL store / fromFile unchanged.
- Optional metal audit: PE Arm64 check → `native-packages.json` (not default product path).

## Catalog maintenance

- Verify arm64 via `winget show` / scoop manifest when adding entries; run `just packages-check` after catalog edits (host dry-run; not part of `just check`).
- Scoop: declare **`scoopBucket`** where needed (`extras` for komorebi/whkd); bootstrap adds buckets before install.

## Wizard

- Chips = catalog keys; compose via `ResolvePackageChips`. Configure **Advanced packages** overrides chips (install ids / WSL tokens).

## Evidence

- Smoke/metal with `packages.winget`: guest `native-packages.json` (Smoke pull + assert); metal pre-wipe checks staged `payload/jobs.json` for audit + arm64 winget jobs.
