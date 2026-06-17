# Codebase Concerns

Snapshot note: this document reflects the current development state of the repo as scanned on 2026-06-18. It is an onboarding/audit snapshot, not a continuous authoritative source of truth.

## Core Sections (Required)

### 1) Top Risks (Prioritized)

| Severity | Concern | Evidence | Impact | Suggested action |
|----------|---------|----------|--------|------------------|
| High | Contract drift across Rust UI intent, backend option/profile authoring, JSON schemas (profile/manifest/builddelta/agentstate/uiintent), setup payloads, and tests. | `apps/gui/src/core/profile.rs`, `apps/gui/src/core/options.rs`, `schemas/winmint.uiintent.schema.json`, `schemas/winmint.builddelta.schema.json`, `src/runtime/image/Private/Config/OptionCatalog.ps1`, `src/runtime/image/Private/Config/ProfileAuthoring.ps1`, `src/runtime/image/Private/Audit.ps1`, `tools/ui-bridge/New-UiBuildProfile.ps1`, `tests/contract/Test-UiContractSpine.ps1` | A field can appear correct in the UI but build, setup, or the BuildDelta audit can consume/emit a different shape. | Keep schema, Rust builder/options, backend catalog/authoring modules, the BuildDelta audit catalog, bridge adapter, and contract tests in the same change. |
| High | Build engine and setup code depend on mutable Windows host state and admin-only tooling. | `src/runtime/image/Engine.ps1`, `src/runtime/image/Private/Image/Staging.ps1`, `tools/ui-bridge/Get-UiIsoMetadata.ps1`, `tools/vm/Build-And-TestVm.ps1` | Reproducibility and CI coverage are limited when DISM/ADK/Hyper-V/source ISO state changes. | Continue expanding dry-run/static contracts and document host preflight failures precisely. |
| Medium | Backend module layer was over-scaffolded; only `WinMint.Bootstrap`, `WinMint.Profile`, and `WinMint.Engine` remain. `WinMint.Engine` dot-sources `WinMint.ps1` as the single runtime load order. | `src/runtime/modules/WinMint.Engine/WinMint.Engine.psm1`, `src/runtime/image/WinMint.ps1`, `WinMint-CLI.ps1` | Reintroducing per-area module wrappers without consumers recreates dual-composition drift. | Add runtime files to `WinMint.ps1` only; keep `WinMint.Engine` as a thin import shim. |
| Medium | Several core files exceed 500 lines and mix multiple related responsibilities. | `src/runtime/setup/FirstLogon.Support.ps1`, `src/runtime/image/Private/Manifest.ps1`, `src/runtime/image/Private/Config/Profile.ps1`, `src/runtime/image/Private/Image/Staging.ps1`, `apps/gui/src/main.rs` | Higher review cost and harder surgical changes. | Extract only along existing layer boundaries when a change touches one of these areas. |
| Medium | Network/download supply chain spans GitHub latest releases, Microsoft Catalog scraping, package managers, and raw helper images. | `winmint.ps1`, `src/runtime/image/Private/UpdatePayloads.ps1`, `src/runtime/image/Private/PayloadStore.ps1`, `src/runtime/image/Private/UsbMedia.ps1`, `config/packages.json` | Upstream changes can break builds or alter payloads. | Resolve non-Microsoft GitHub assets via `/releases/latest`, record resolved tag/hash in manifests, and keep SHA256 verification where upstream publishes it. |
| Low | Validation command intent was inconsistent between docs and implementation. | `AGENTS.md`, `tools/validation/Validate.ps1`, `tools/validation/Modules/Core.ps1`, `.github/workflows/ci.yml` | Users or agents may believe PSScriptAnalyzer ran when default local validation skipped it. | Resolved: local default stays fast; CI runs `-RunAnalyzer`. |
| Low | `docs/codebase/` snapshots can go stale or be mistaken for authoritative product docs. | `docs/codebase/`, `config/release-manifest.json`, `docs/Project-Structure.md` | Contributors may follow stale audit notes instead of current contracts. | Keep them excluded from release bundles and defer to `README.md`, `AGENTS.md`, schemas, and tests when conflicts appear. |

### 2) Technical Debt

| Debt item | Why it exists | Where | Risk if ignored | Suggested fix |
|-----------|---------------|-------|-----------------|---------------|
| Large FirstLogon support module | Accumulated live-user setup helpers in one phase file. | `src/runtime/setup/FirstLogon.Support.ps1` | Small preference changes can affect unrelated first-logon behavior. | Extract by domain only when a domain changes and contract tests cover the split. |
| Manifest/report split is recent | Manifest lifecycle moved into a private manifest module while report compatibility names remain available. | `src/runtime/image/Private/Manifest.ps1`, `src/runtime/image/Reports.ps1` | Callers can drift back to report-file internals or bypass manifest adapters. | Keep new manifest behavior behind `Private/Manifest.ps1` helpers and preserve contract tests for final manifest output. |
| Dual GUI/profile contract surface | Rust builds typed UI intent while PowerShell owns final profile shape. | `apps/gui/src/core/profile.rs`, `src/runtime/image/Private/Config/OptionCatalog.ps1`, `src/runtime/image/Private/Config/ProfileAuthoring.ps1`, `tools/ui-bridge/New-UiBuildProfile.ps1` | Field defaults can diverge. | Treat `Test-UiContractSpine.ps1` as mandatory for every UI/profile change. |
| Setup payload staging split is recent | Setup/FirstLogon payload staging moved out of `Unattend.ps1` into a dedicated image module. | `src/runtime/image/Private/Image/SetupPayloadStaging.ps1`, `src/runtime/image/Private/Image/Unattend.ps1`, `tests/contract/Test-InstallPlanContract.ps1` | Required setup artifacts can drift from install-plan facts if callers bypass the staging module. | Keep `Get-WinMintSetupPayloadRequiredArtifacts` as the test/report seam when changing staged setup files. |
| UI option catalog alignment | Serialized option tokens live in `apps/gui/src/core/options.rs` and the PowerShell backend catalog; GPUI display rows adapt them. | `apps/gui/src/core/options.rs`, `src/runtime/image/Private/Config/OptionCatalog.ps1`, `apps/gui/src/options.rs`, `schemas/winmint.uiintent.schema.json` | Adding a UI choice in one layer can silently produce unsupported profile values. | Update GUI core options, backend option catalog, GPUI display rows, schema enums, bridge conversion, and UI contract tests together. |
| BuildDelta schema trimmed to consumed fields | Provenance/requires/suppressedBy fields were write-only; record model now matches GUI/report readers. | `schemas/winmint.builddelta.schema.json`, `src/runtime/image/Private/Audit.ps1`, `apps/gui/src/bridge.rs`, `src/runtime/image/Reports.ps1` | Re-expanding the record without a reader reintroduces dead contract surface. | Add fields only when a consumer reads them. |
| Stable-channel enforcement | Latest stable release is intended, but remote acquisition paths still need explicit guards where upstream APIs expose preview/nightly assets. | `src/runtime/image/Private/PayloadStore.ps1`, `src/runtime/image/Private/UpdatePayloads.ps1` | Preview payloads can enter builds accidentally if matching logic is too broad. | Add focused assertions or filters around channel selection when touching acquisition code. |
| Lint compat target trails runtime requirement | `PSUseCompatibleSyntax` targets `7.3` while modules declare `#Requires -Version 7.6` and release readiness states `7.6.2+`. | `PSScriptAnalyzerSettings.psd1`, `src/runtime/modules/WinMint.Engine/WinMint.Engine.psm1`, `config/release-readiness.json` | The analyzer could flag valid 7.6 syntax or miss 7.4–7.6-only constructs, weakening the compat check. | Bump the `PSUseCompatibleSyntax` target to match the supported runtime when convenient. |

### 3) Security Concerns

| Risk | OWASP category (if applicable) | Evidence | Current mitigation | Gap |
|------|--------------------------------|----------|--------------------|-----|
| Local-account password can be passed on the CLI. | N/A local tooling secret handling | `src/runtime/image/Cli.ps1`, `src/runtime/image/Private/Headless.ps1`, `PSScriptAnalyzerSettings.psd1` | Alternatives exist via `-PasswordPath` and `-PasswordEnvVar`; lint exclusion documents the deliberate allowance. | Local-only tool: plaintext in authored profiles is fine; published build artifacts omit secrets; do not commit profiles with `passwordIncluded: true`. |
| Remote bootstrap uses `irm | iex` distribution path. | N/A supply chain | `README.md`, `docs/Distribution.md`, `winmint.ps1`, `cloudflare/winmint/src/index.js` | Bootstrap verifies release zip SHA256 and serves plain text with `nosniff`; inspect-first path is documented. | Trust model for Cloudflare/GitHub compromise is `[TODO]`. |
| Downloaded latest-release/package payloads can change upstream. | N/A supply chain | `src/runtime/image/Private/PayloadStore.ps1`, `src/runtime/image/Private/Image/Packages.ps1`, `src/runtime/image/Private/Image/Staging.ps1`, `config/packages.json` | Some payloads are hashed, signed, or recorded in manifests; Microsoft Catalog downloads verify SHA256 metadata. GitHub fetches use `/releases/latest` (excludes drafts/prereleases). | Record resolved tag/hash in `BuildManifest.json` for auditability; keep the pinned SHA256 Everything ARM64 exception documented. |
| Destructive USB/disk operations exist. | N/A local destructive operation | `src/runtime/image/Private/UsbMedia.ps1`, `src/runtime/image/Private/Console/Review.ps1`, `README.md` | Explicit flags, disk confirmation, and typed/destructive confirmations are present. | Automated destructive-path acceptance coverage is `[TODO]`. |

### 4) Performance and Scaling Concerns

| Concern | Evidence | Current symptom | Scaling risk | Suggested improvement |
|---------|----------|-----------------|-------------|-----------------------|
| WIM servicing can be long-running and host-sensitive. | `src/runtime/image/Private/Pipeline.ps1`, `src/runtime/image/Private/IntermediatesCache.ps1`, `src/runtime/image/Private/IsoStageCache.ps1` | Cache modules exist for staged ISO/intermediates/serviced WIMs. | Cache fingerprint bugs can trade speed for stale output. | Keep cache fingerprints tied to source ISO, profile, toolchain, drivers, and update payloads. |
| Stable update payload acquisition scrapes/searches remote catalogs. | `src/runtime/image/Private/UpdatePayloads.ps1` | Build time and success depend on Microsoft Catalog availability/shape. | Catalog changes can break opt-in update builds. | Add more contract fixtures around catalog parsing and manifest verification. |
| FirstLogon package installs are sequential through agent steps. | `src/runtime/firstlogon/Agent.Runtime.ps1`, `src/runtime/firstlogon/Modules/*.ps1` | Simpler logs/state, slower first logon. | More selected tools means longer first-logon setup. | Parallelize only after state/log semantics are designed and tested. |

### 5) Fragile/High-Churn Areas

| Area | Why fragile | Churn signal | Safe change strategy |
|------|-------------|--------------|----------------------|
| `tests/contract/ProfileInvariantTests/StaticAssertions.ps1` | Encodes many static product/architecture guards. | Highest recent churn in scan output. | Update assertions with the behavior change, not after. |
| `README.md` / `AGENTS.md` | Product stance and implementation contract evolve together. | Both are high-churn files in recent history. | Update README for user behavior and AGENTS for agent/repo contracts in the same PR when applicable. |
| `src/runtime/image/Private/Config/Profile.ps1` | Central profile/default normalization. | High churn and broad downstream consumers. | Run profile invariants, UI contract spine, and schema validation for every edit. |
| `src/runtime/image/Engine.ps1` and `src/runtime/image/Private/Pipeline.ps1` | Host preflight, manifest lifecycle, and build orchestration. | High churn plus Windows/DISM side effects. | Prefer small changes with dry-run and contract verification. |
| `apps/gui/src/main.rs` | Main wizard state/rendering is concentrated in one file. | High churn and >500 lines. | Keep components in `components.rs` until stateful extraction is justified by local conventions. |

### 6) Resolved Product/Repo Decisions

1. PowerShell owns the backend and all real work. GPUI/Rust is a frontend layer, and the actual build logic stays headless.
2. `docs/codebase/` is a current-development snapshot for onboarding/audits, not a continuous authoritative source of truth, and should not ship in release bundles.
3. Starship is baseline behavior by default with the Nerd Font symbols preset.
4. Testing is important for an ISO builder, but the project should stay pragmatic rather than chase overkill coverage. Fast contract/static tests plus targeted dry-run/VM acceptance are the preferred shape.
5. External acquisition should use latest stable releases via `/releases/latest` for GitHub assets. Nightly, preview, beta, and canary channels are not intended product behavior.
6. The intended current license expression is `GPL-2.0-or-later`; the app is alpha and the license can change later if needed.
7. PSScriptAnalyzer is opt-in locally (`Validate.ps1 -RunAnalyzer`) and enforced in CI.
8. Cloudflare Worker deploy credentials are maintainer-held, least-privilege API tokens rotated manually; never stored in repo or CI until deploy automation exists.
9. HTTP download retry/timeout policy should centralize in a shared helper over time; DISM/package-manager calls and FirstLogon step retries remain tool-specific.
10. Local-account passwords may live in plaintext authored profiles (local-only, no telemetry); engine redacts published `WinMint-BuildProfile.json` for resume correctness; manifest/delta carry no password; do not commit `passwordIncluded: true` profiles.

### 7) Simplification Notes (2026-06-18)

Removed or demoted over-built surfaces: five unused `src/runtime/modules/` packages, unwired first-logon GPUI demo deleted, `crates/winmint-core` folded into `apps/gui/src/core/`, BuildDelta record trimmed to consumed fields, release-readiness/hardware-acceptance prose assertions dropped from blocking validation.

### 8) Evidence

- `AGENTS.md`
- `README.md`
- `roadmap.md`
- `Cargo.toml`
- `THIRD_PARTY_NOTICES.md`
- `config/release-manifest.json`
- `src/runtime/modules/WinMint.ModuleLoader.ps1`
- `src/runtime/image/Private/Config/Profile.ps1`
- `src/runtime/image/Private/Config/OptionCatalog.ps1`
- `src/runtime/image/Private/Audit.ps1`
- `schemas/winmint.builddelta.schema.json`
- `src/runtime/image/Private/Pipeline.ps1`
- `src/runtime/image/Private/Manifest.ps1`
- `src/runtime/image/Reports.ps1`
- `src/runtime/firstlogon/Agent.Runtime.ps1`
- `tests/contract/Test-UiContractSpine.ps1`
- `PSScriptAnalyzerSettings.psd1`
