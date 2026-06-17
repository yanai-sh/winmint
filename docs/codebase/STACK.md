# Technology Stack

Snapshot note: this document reflects the current development state of the repo as scanned on 2026-06-18. It is an onboarding/audit snapshot, not a continuous authoritative source of truth.

## Core Sections (Required)

### 1) Runtime Summary

| Area | Value | Evidence |
|------|-------|----------|
| Primary language | PowerShell for the headless backend and real product work: servicing, setup, first-logon, profile/report logic, validation, release, and VM automation. | `WinMint-CLI.ps1`, `WinMint-GUI.ps1`, `src/runtime/image/WinMint.ps1`, `src/runtime/firstlogon/Start-WinMintAgent.ps1`, `tools/validation/Validate.ps1` |
| Secondary languages | Rust for the shipped GPUI frontend (including in-crate UI intent helpers under `apps/gui/src/core/`); JavaScript for the Cloudflare bootstrap Worker. | `Cargo.toml`, `apps/gui/src/main.rs`, `apps/gui/src/core/profile.rs`, `cloudflare/winmint/src/index.js` |
| Runtime + version | Backend/runtime scripts require PowerShell 7.6.2+ (`#Requires -Version 7.6` in the module `.psm1` files; `7.6.2+` in `config/release-readiness.json`). The remote bootstrap entry (`WinMint-CLI.ps1`, `winmint.ps1`) starts in Windows PowerShell 5.1, self-elevates/relaunches, then runs under 7.6.2+. Rust workspace uses edition 2021. Exact Rust compiler version is `[TODO]`. | `WinMint-CLI.ps1`, `src/runtime/modules/WinMint.Engine/WinMint.Engine.psm1`, `winmint.ps1`, `config/release-readiness.json`, `Cargo.toml` |
| Package manager | Cargo for Rust workspace dependencies; winget/msstore/Scoop are runtime package sources; `bunx wrangler@latest` is the documented Worker deploy command. The repo has no root Node package manifest. | `Cargo.toml`, `config/packages.json`, `cloudflare/winmint/README.md` |
| Module/build system | Thin PowerShell modules (`WinMint.Bootstrap`, `WinMint.Profile`, `WinMint.Engine` dot-sourcing `WinMint.ps1`); Cargo workspace with `apps/gui` only. Desktop shell presets bundle via `assets/runtime/desktop/*/preset.manifest.json`. | `src/runtime/modules/WinMint.Engine/WinMint.Engine.psm1`, `WinMint-CLI.ps1`, `Cargo.toml` |

### 2) Production Frameworks and Dependencies

| Dependency | Version | Role in system | Evidence |
|------------|---------|----------------|----------|
| `gpui` | `0.2.2` | Primary shipped GUI framework. | `Cargo.toml`, `apps/gui/Cargo.toml` |
| `gpui-animation` | `0.2.4` | GUI hover/state animation dependency. | `Cargo.toml`, `apps/gui/Cargo.toml` |
| `serde` / `serde_json` | `1.0` | JSON contract serialization/deserialization in the GPUI frontend. | `Cargo.toml`, `apps/gui/Cargo.toml` |
| `embed-resource` | `3.0` | Windows resource embedding for the shipped GUI executable. | `Cargo.toml`, `apps/gui/build.rs` |
| DISM / Storage / Hyper-V PowerShell modules | Host-provided | ISO mounting, WIM servicing, driver injection, and VM acceptance tooling. | `tools/ui-bridge/Get-UiIsoMetadata.ps1`, `src/runtime/image/Private/Image/Staging.ps1`, `tools/vm/Build-And-TestVm.ps1` |
| winget / msstore / Scoop | Host or installed during setup | Live-user app/tool installs from the package catalog. | `config/packages.json`, `src/runtime/firstlogon/Agent.Runtime.ps1`, `src/runtime/firstlogon/Modules/PackageManagers.ps1` |

### 3) Development Toolchain

| Tool | Purpose | Evidence |
|------|---------|----------|
| PSScriptAnalyzer | Optional PowerShell linting locally (`Validate.ps1 -RunAnalyzer`); enforced in CI. Repo-specific exclusions and PS 7.3 syntax checks. | `PSScriptAnalyzerSettings.psd1`, `tools/validation/Modules/Core.ps1`, `.github/workflows/ci.yml` |
| PowerShell parser / JSON / XML validation | Static validation for scripts and config contracts. | `tools/validation/Validate.ps1`, `tools/validation/Modules/Core.ps1`, `tools/validation/Modules/Schemas.ps1` |
| Cargo | Rust checking and tests for GUI/core crates. | `.github/workflows/ci.yml`, `tools/validation/Modules/Core.ps1` |
| GitHub Actions | CI and release automation. | `.github/workflows/ci.yml`, `.github/workflows/release.yml` |
| Wrangler via `bunx` | Cloudflare Worker deployment. | `cloudflare/winmint/README.md`, `cloudflare/winmint/wrangler.jsonc` |

### 4) Key Commands

```powershell
pwsh -NoProfile -File tools\validation\Validate.ps1
pwsh -NoProfile -File tools\validation\Validate.ps1 -RunAnalyzer
pwsh -NoProfile -File tests\contract\Test-ProfileInvariants.ps1
pwsh -NoProfile -File tests\contract\Test-Fast.ps1
cargo test --manifest-path apps\gui\Cargo.toml
pwsh -NoProfile -File WinMint-CLI.ps1 new BuildProfile.json
pwsh -NoProfile -File WinMint-CLI.ps1 build BuildProfile.json -DryRun
pwsh -NoProfile -File tools\release\New-WinMintReleaseBundle.ps1 -Version v0.2.0
```

### 5) Environment and Config

- Config sources: `config/packages.json`, `config/appx-removal.json`, `config/ai-removal.json`, `config/tweaks.json`, `config/release-manifest.json`, `config/release-readiness.json`, `config/hardware-acceptance.json`, `config/surface-drivers.json`, `config/build-profiles/*.json`, `config/autounattend.xml`, `schemas/winmint.*.schema.json` (profile, manifest, builddelta, agentstate, uiintent).
- Required env vars: `LOCALAPPDATA` is required by `winmint.ps1`; `WINMINT_ENABLE_EXPERIMENTAL_AI_REMOVAL=1` is required only for aggressive experimental AI removal; `PasswordEnvVar` is a user-selected CLI parameter name read by `Resolve-WinMintHeadlessSecret`; other required variables are `[TODO]`.
- Deployment/runtime constraints: Windows 11 build host, PowerShell 7.6.2+ (bootstrap entry tolerates Windows PowerShell 5.1 before relaunch), Administrator rights for build/validate flows, source Windows 11 25H2+ ISO, compatible DISM/ADK tooling, and `oscdimg.exe` for final ISO assembly.

### 6) Evidence

- `README.md`
- `AGENTS.md`
- `Cargo.toml`
- `config/packages.json`
- `src/runtime/image/WinMint.ps1`
- `src/runtime/image/Cli.ps1`
- `src/runtime/firstlogon/Agent.Runtime.ps1`
- `tools/validation/Validate.ps1`
- `.github/workflows/ci.yml`
- `cloudflare/winmint/wrangler.jsonc`
