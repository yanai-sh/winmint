# Spec: Package catalog + ARM64 harvest

**Status:** Accepted (2026-08-05)  
**Authority:** [ADR-010](../decisions/ADR-010-arm64-package-policy.md)

## Catalog (`config/packages.json`)

- **Catalog key** — Wizard chip id (`zen-browser`).
- **Install id** — Profile `packages.winget` / `scoop` value (`Zen-Team.Zen-Browser`).

## Plan

- Validate all package ids against catalog; arm64 image rejects entries without `arm64` in `architectures`.
- Winget jobs: optional `wingetArchitecture: arm64`. WSL: `wslInstallKind` + fromFile metadata for NixOS-WSL.
- Non-empty winget on arm64 ⇒ `package.auditNative` job (`auditStrict` from `RunOptions.PackageAuditStrict`).

## Guest

- Winget: `--architecture arm64` when job field set.
- WSL store: `wsl --install -d {id} --no-launch`. fromFile: download GitHub asset then `--install --from-file`.
- Audit: PE Arm64 check for known GUI paths → `%ProgramData%\WinMint\evidence\native-packages.json`.

## Wizard

- Chips = catalog keys; compose via `ResolvePackageChips`. Configure **Advanced packages** overrides chips (install ids / WSL tokens).

## Evidence

- Smoke/metal with `packages.winget`: guest `native-packages.json` (Smoke pull + assert); metal pre-wipe checks staged `payload/jobs.json` for audit + arm64 winget jobs.
