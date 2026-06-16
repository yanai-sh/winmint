# Technology Stack

Snapshot note: this document reflects the current development state of the repo as scanned on 2026-06-16. It is an onboarding/audit snapshot, not a continuous authoritative source of truth.

## Core Sections (Required)

### 1) Runtime Summary

| Area | Value | Evidence |
|------|-------|----------|
| Primary language | PowerShell for the headless backend and real product work: servicing, setup, first-logon, profile/report logic, validation, release, and VM automation. | `WinMint-CLI.ps1`, `WinMint-GUI.ps1`, `src/runtime/image/WinMint.ps1`, `src/runtime/firstlogon/Start-WinMintAgent.ps1`, `tools/validation/Validate.ps1` |
| Secondary languages | Rust for GPUI frontend layers and shared UI/profile intent helpers; JavaScript for the Cloudflare bootstrap Worker. | `Cargo.toml`, `apps/gui/src/main.rs`, `apps/firstlogon-gui/src/main.rs`, `crates/winmint-core/src/profile.rs`, `cloudflare/winmint/src/index.js` |
| Runtime + version | Project scripts require PowerShell 7.3+; remote bootstrap starts in Windows PowerShell 5.1 and then requires PowerShell 7.3+; Rust workspace uses edition 2021. Exact Rust compiler version is `[TODO]`. | `WinMint-CLI.ps1`, `WinMint-GUI.ps1`, `winmint.ps1`, `Cargo.toml`, `.github/workflows/ci.yml` |
| Package manager | Cargo for Rust workspace dependencies; winget/msstore/Scoop are runtime package sources; `bunx wrangler@latest` is the documented Worker deploy command. The repo has no root Node package manifest. | `Cargo.toml`, `config/packages.json`, `cloudflare/winmint/README.md` |
| Module/build system | PowerShell dot-sourced runtime modules; Cargo workspace with `apps/firstlogon-gui`, `apps/gui`, and `crates/winmint-core`; Wrangler Worker config for the bootstrap alias. | `src/runtime/image/WinMint.ps1`, `Cargo.toml`, `cloudflare/winmint/wrangler.jsonc` |

### 2) Production Frameworks and Dependencies

| Dependency | Version | Role in system | Evidence |
|------------|---------|----------------|----------|
| `gpui` | `0.2.2` | Primary shipped GUI framework. | `Cargo.toml`, `apps/gui/Cargo.toml` |
| `gpui-animation` | `0.2.4` | GUI hover/state animation dependency. | `Cargo.toml`, `apps/gui/Cargo.toml` |
| `gpui-component` | `0.5.1` | FirstLogon GUI component set. | `Cargo.toml`, `apps/firstlogon-gui/Cargo.toml` |
| `serde` / `serde_json` | `1.0` | JSON contract serialization/deserialization in Rust front ends and core helpers. | `Cargo.toml`, `crates/winmint-core/Cargo.toml` |
| `windows-sys` | `0.61.2` | Windows API calls used by the FirstLogon GPUI window chrome helper. | `apps/firstlogon-gui/Cargo.toml`, `apps/firstlogon-gui/src/main.rs` |
| `embed-resource` | `3.0` | Windows resource embedding for GUI executables. | `Cargo.toml`, `apps/gui/build.rs`, `apps/firstlogon-gui/build.rs` |
| DISM / Storage / Hyper-V PowerShell modules | Host-provided | ISO mounting, WIM servicing, driver injection, and VM acceptance tooling. | `tools/ui-bridge/Get-UiIsoMetadata.ps1`, `src/runtime/image/Private/Image/Staging.ps1`, `tools/vm/Build-And-TestVm.ps1` |
| winget / msstore / Scoop | Host or installed during setup | Live-user app/tool installs from the package catalog. | `config/packages.json`, `src/runtime/firstlogon/Agent.Runtime.ps1`, `src/runtime/firstlogon/Modules/PackageManagers.ps1` |

### 3) Development Toolchain

| Tool | Purpose | Evidence |
|------|---------|----------|
| PSScriptAnalyzer | Optional PowerShell linting with repo-specific exclusions and PS 7.3 syntax checks; `Validate.ps1` skips it unless `-RunAnalyzer` is passed. | `PSScriptAnalyzerSettings.psd1`, `tools/validation/Modules/Core.ps1` |
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
cargo test --manifest-path crates\winmint-core\Cargo.toml
cargo check --manifest-path apps\gui\Cargo.toml
cargo test --manifest-path apps\gui\Cargo.toml
pwsh -NoProfile -File WinMint-CLI.ps1 new BuildProfile.json
pwsh -NoProfile -File WinMint-CLI.ps1 build BuildProfile.json -DryRun
pwsh -NoProfile -File tools\release\New-WinMintReleaseBundle.ps1 -Version v0.2.0
```

### 5) Environment and Config

- Config sources: `config/packages.json`, `config/appx-removal.json`, `config/ai-removal.json`, `config/tweaks.json`, `config/release-manifest.json`, `config/autounattend.xml`, `schemas/winmint.*.schema.json`.
- Required env vars: `LOCALAPPDATA` is required by `winmint.ps1`; `WINMINT_ENABLE_EXPERIMENTAL_AI_REMOVAL=1` is required only for aggressive experimental AI removal; `PasswordEnvVar` is a user-selected CLI parameter name read by `Resolve-WinMintHeadlessSecret`; other required variables are `[TODO]`.
- Deployment/runtime constraints: Windows 11 build host, PowerShell 7.3+, Administrator rights for build/validate flows, source Windows 11 25H2+ ISO, compatible DISM/ADK tooling, and `oscdimg.exe` for final ISO assembly.

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
