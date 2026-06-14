# Codebase Concerns

## 1) Top Risks (Prioritized)

| Severity | Concern | Evidence | Impact | Suggested action |
|----------|---------|----------|--------|------------------|
| High | License metadata differs between docs and Cargo. | `README.md` and `THIRD_PARTY_NOTICES.md` say GPL-2.0-or-later; root `Cargo.toml` says `license = "GPL-2.0-only"`. | Release metadata and legal terms can disagree between packaged docs and Rust crates. | [ASK USER] Pick the intended license expression and update the other source to match. |
| Medium | `crates/winmintctl/target` exists without an active source crate. | `Get-ChildItem crates\winmintctl -Force -Recurse` shows only `target/`; `Cargo.toml` workspace members are `apps/gui` and `crates/winmint-core`; `Get-Content crates\winmintctl\Cargo.toml` fails. | Maintainers and scanners may treat ignored build output as a missing or half-removed crate. | [ASK USER] Decide whether to remove the ignored artifact, restore the crate, or document it as intentionally local. |
| Medium | Cloudflare `/cli` wrapper must stay profile-backed. | `cloudflare/winmint/src/index.js` keeps bootstrap/headless profile parameters; `AGENTS.md` says configuration flags live only on `new`. | Reintroducing flat flags would recreate a parallel command surface. | Keep `Test-CloudflareWorkerContract.ps1` checking that legacy flags stay absent. |
| Medium | Several orchestration files are long and cover multiple concerns. | Local line-count output: `src/runtime/setup/FirstLogon.Support.ps1` 1451, `src/runtime/image/Reports.ps1` 1153, `src/runtime/image/Private/Image/Staging.ps1` 819, `src/runtime/image/Private/Config/Profile.ps1` 810, `src/runtime/firstlogon/Agent.Runtime.ps1` 681, `apps/gui/src/main.rs` 632. | Higher review cost and greater regression risk when changing setup/profile/report/GUI behavior. | Extract only when a stable boundary appears; keep tests around each extracted contract. |
| Medium | Release and setup flows handle sensitive local-account passwords. | `src/runtime/image/Engine.ps1` strips password/autologon from public profile artifacts; `src/runtime/setup/SetupComplete.ps1` deletes Panther unattend files. | Any missed cleanup or ACL gap can expose install credentials on the build host or target system. | Keep static tests for credential cleanup and ACL handling; audit dry-run artifacts before release. |
| Medium | Full ISO servicing depends on local Windows/ADK/DISM/administrator state. | `README.md`, `src/runtime/image/Private/Image/Staging.ps1`, `tools/ui-bridge/Get-UiIsoMetadata.ps1`. | CI can validate contracts but cannot fully prove all host-specific build paths. | Maintain VM acceptance scripts and periodically run full ARM64/x64 install loops. |

## 2) Technical Debt

| Debt item | Why it exists | Where | Risk if ignored | Suggested fix |
|-----------|---------------|-------|-----------------|---------------|
| Ignored Rust build output sits under a crate-like path. | A previous `winmintctl` build appears to have left `target/` under `crates/winmintctl`. | `crates/winmintctl/target`, `.gitignore`, `Cargo.toml` | Scans and maintainers can misread the tree as an incomplete crate. | Remove the ignored directory if it is not intentionally preserved; restore source if `winmintctl` is still planned. |
| Cloudflare CLI wrapper no-legacy policy needs a guard. | Previous headless model exposed flat flags; product stance is now profile-backed verbs. | `cloudflare/winmint/src/index.js`, `winmint.ps1`, `src/runtime/image/Cli.ps1` | Legacy flags could return accidentally. | Keep a contract assertion that `/cli` does not expose removed flags. |
| Large setup/profile/report modules. | Windows setup orchestration has many tightly ordered phases. | `src/runtime/setup/FirstLogon.Support.ps1`, `src/runtime/image/Reports.ps1`, `src/runtime/image/Private/Image/Staging.ps1`, `src/runtime/image/Private/Config/Profile.ps1` | Local edits can unintentionally affect unrelated phases. | Split only around tested contracts such as profile normalization, cleanup, and report writers. |
| No coverage reporting. | Tests are script-driven contract checks. | `.github/workflows/ci.yml`, `tools/validation/Validate.ps1` | Unclear behavioral coverage for edge cases. | Add lightweight coverage only if it produces actionable signal for PowerShell/Rust paths. |

## 3) Security Concerns

| Risk | OWASP category | Evidence | Current mitigation | Gap |
|------|----------------|----------|--------------------|-----|
| Local-account password appears in unattend/setup artifacts during build/install. | N/A desktop/install tooling | `src/runtime/image/Engine.ps1`, `src/runtime/setup/SetupComplete.ps1`, `src/runtime/image/Private/Pipeline.ps1` | Work directories get restricted ACLs; public profile strips secrets; SetupComplete deletes Panther unattend files. | Needs recurring validation on real installs and dry-run artifact review. |
| Remote bootstrap uses `irm | iex`. | N/A | `README.md`, `docs/Distribution.md`, `winmint.ps1` | Inspect-first path documented; bootstrap now requires the matching `.sha256` asset and verifies the selected zip before install. | No signature verification found. |
| Downloads from GitHub/latest package releases. | N/A supply chain | `src/runtime/image/Private/Image/Assets.ps1`, `src/runtime/image/Private/Image/Packages.ps1`, `winmint.ps1` | Some downloaded payloads are hashed and recorded in manifests. | Upstream release pinning/signature policy is [TODO]. |
| Package-manager installs at FirstLogon. | N/A supply chain | `config/packages.json`, `src/runtime/firstlogon/Agent.Runtime.ps1` | Catalog restricts source values to winget/store/scoop; validation checks package manifest architecture/source. | Package version pinning defaults to `latest`; exact reproducibility is limited. |

## 4) Performance and Scaling Concerns

| Concern | Evidence | Current symptom | Scaling risk | Suggested improvement |
|---------|----------|-----------------|-------------|-----------------------|
| ISO/WIM servicing is inherently heavy. | `src/runtime/image/Private/Pipeline.ps1`, `src/runtime/image/Private/Image/Staging.ps1` | Pipeline comments mention multi-minute ISO assembly and 30-60 minute DISM servicing avoided by cache on hit. | Larger source ISOs or multi-edition servicing increase build time. | Preserve serviced WIM and ISO stage caches; keep cache-key contract tests current. |
| Large source files slow review. | Local line-count output listed multiple files over 800 lines. | Each change needs more context. | Higher defect probability in setup/profile/report edits. | Extract narrowly around tested contracts; avoid broad rewrites. |
| External package installs are serialized through agent steps. | `src/runtime/firstlogon/Start-WinMintAgent.ps1`, `src/runtime/firstlogon/Agent.Runtime.ps1` | Modules run step-by-step and command output is serialized. | FirstLogon duration grows with selected tools. | Only parallelize after proving package managers and installers tolerate it. |
| Validation can be host-dependent. | `tools/validation/Validate.ps1`, `tests/contract/Test-Integration.ps1` | Integration ISO dry-run requires admin and fixtures. | Local machines may get different confidence levels. | Keep fast suite deterministic; document fixture requirements. |

## 5) Fragile/High-Churn Areas

| Area | Why fragile | Churn signal | Safe change strategy |
|------|-------------|--------------|----------------------|
| `AGENTS.md`, `README.md`, `docs/*.md` | Product contract and user behavior are active design surfaces. | Recent-history output: `AGENTS.md` 12, `README.md` 10, `docs/Project-Structure.md` 8, `docs/Windows-Debloat-Strategy.md` 8. | Update docs with behavior/schema/test changes in the same commit. |
| CLI/profile engine | Public verb surface and schema v3 profile defaults. | Recent-history output: `WinMint-CLI.ps1` 12, `tests/contract/ProfileInvariantTests/StaticAssertions.ps1` 15, `tests/contract/Test-ProfileInvariants.ps1` 9, schema 7. | Add or update `Test-CliMatrix.ps1` and profile invariant assertions before changing flags/contracts. |
| Image pipeline/setup staging | DISM, WIM, unattended setup, and setup script staging are tightly coupled. | Large files and recent-history output include `src/runtime/image/Reports.ps1`, `src/runtime/image/Private/Config/Profile.ps1`, and setup modules. | Run parser/static guards and do at least dry-run integration with a fixture ISO. |
| FirstLogon/setup cleanup | Handles credentials, autologon, package installs, retry state, and user cleanup. | Large files and many modules under `src/runtime/setup` and `src/runtime/firstlogon`. | Keep state schema and cleanup tests current; make optional modules non-blocking unless explicitly required. |

## 6) `[ASK USER]` Questions

1. [ASK USER] Should the project license metadata be `GPL-2.0-or-later` everywhere, or should the README/notice files be changed to match Cargo's `GPL-2.0-only`?
2. [ASK USER] Is `crates/winmintctl/target` just local generated residue to delete, or should a `winmintctl` crate be restored/documented?

## 7) Evidence

- `git status --short` terminal output
- `Cargo.toml`
- `README.md`
- `THIRD_PARTY_NOTICES.md`
- `.gitignore`
- `crates/winmintctl/target` terminal output
- `cloudflare/winmint/src/index.js`
- `winmint.ps1`
- `WinMint-CLI.ps1`
- `src/runtime/image/WinMint.ps1`
- `src/runtime/image/Private/Pipeline.ps1`
- `src/runtime/setup/SetupComplete.ps1`
- `src/runtime/setup/FirstLogon.ps1`
- `src/runtime/firstlogon/Agent.Runtime.ps1`
- `docs/Project-Structure.md`
- `tools/validation/Validate.ps1`
