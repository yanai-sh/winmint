# Spec: Alpha package program

**Date:** 2026-08-06  
**Status:** Accepted  
**Authority:** [ADR-011](../decisions/ADR-011-alpha-posture-and-package-delegation.md) · [ADR-010](../decisions/ADR-010-arm64-package-policy.md) · [package catalog](2026-08-05-package-catalog-arm64.md)

## Problem Statement

Grill-era defaults (per-job winget, fail-closed on every package, runtime PE audit) block simpler paths now that WinMint has a closed catalog. Docs partially reflect ADR-011 but code and harness still match ticket-sequence behaviour. Catalog `architectures` are unverified; Scoop apps in `extras` fail on fresh bootstrap.

## Solution

1. **Docs consistency** — tiered grill index; stale “locked / C# only / guest pwsh” aligned with ADR-011.
2. **Catalog hygiene** — `scoopBucket` field; maintainer validator in `just check`.
3. **Scoop** — bootstrap required buckets; batch `scoop install`.
4. **Winget** — Plan emits `payload/winget-import.json`; Supervisor runs one `winget import` job (arm64 via `InitialOverrideArguments`).
5. **Best-effort packages** — failures recorded; session continues; demote default `package.auditNative`.
6. **Harness** — metal/smoke asserts for import artifact and package evidence.

**Out of scope:** `winget configure` as default; `scoop-aarch64` third-party bucket.

## User Stories

1. As a maintainer, I want `packages.json` validated in CI, so arm64 URLs and winget ids are real before ship.
2. As a maintainer, I want komorebi/whkd to install from `extras` without hand-editing the guest, so catalog declares `scoopBucket`.
3. As a solo dev, I want winget packages installed in one batch on ARM64, so FirstLogon is faster and simpler.
4. As a solo dev, I want one failed winget id not to block Explorer unlock, so I can fix it on a usable desktop.
5. As a maintainer, I want metal to opt into strict package asserts, so regression evidence remains available.
6. As an agent, I want grill rows labelled Invariant/Default/Guideline, so I do not treat ticket wording as immutable law.

## Implementation Decisions

### Package phase (`RunOptions.PackagePhase`)

- `PerJob` — legacy one spawn per catalog id (Smoke-friendly).
- `WingetImport` — Plan omits per-id winget jobs when import JSON non-empty; stages `winget-import.json`; one job `kind: winget.import`.
- Default when Profile has winget on arm64 image: `WingetImport`.

Scoop: Plan collapses scoop jobs into one `kind: scoop.batch` when `PackagePhase` allows batch (default batch when ≥1 scoop id).

### Winget import JSON

Generated from Profile + catalog. Schema: winget packages export v2. Per-package `InitialOverrideArguments: "--architecture arm64"` when catalog supports arm64.

### Best-effort

- `ProvisioningSession`: winget/scoop/wsl batch failures append to evidence; do not return Failed unless `RunOptions.PackageStrict` (CLI `--package-strict`).
- Product default: not strict. Metal may pass `--package-strict` or keep audit via `--package-audit-strict`.

### Audit

- Remove default `package.auditNative` from Plan.
- Keep handler + `--package-audit-strict` for metal.

## Testing Decisions

- Plan tests: import JSON emitted; scoop batch job; no default audit job.
- ProvisioningSession fakes: import argv; scoop batch; best-effort continues.
- Catalog validator: embedded JSON + scoop manifest arm64 URL check (HTTP fetch main/extras bucket).
- Harness: optional `-ExpectWingetImport` / package evidence paths.

## Tickets

See GitHub issues [#73–#79](https://github.com/yanai-sh/winmint/issues/73) (filed 2026-08-06, closed on ship).
