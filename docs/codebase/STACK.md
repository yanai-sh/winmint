# Technology Stack

## 1) Runtime Summary

| Area | Value | Evidence |
|------|-------|----------|
| Primary runtime language | PowerShell for shipped Windows servicing/runtime scripts, Rust for the GPUI front end, and JavaScript for the Cloudflare bootstrap alias. | `README.md`, `WinMint-CLI.ps1`, `src/runtime/image/WinMint.ps1`, `apps/gui/Cargo.toml`, `cloudflare/winmint/src/index.js` |
| Runtime + version | PowerShell 7.3+ for project scripts; bootstrap accepts Windows PowerShell 5.1 and then launches PowerShell 7.3+; Rust workspace edition 2021. Exact Rust compiler version is [TODO]. | `WinMint-CLI.ps1`, `WinMint-GUI.ps1`, `winmint.ps1`, `Cargo.toml` |
| Package manager | Cargo for Rust crates; winget, msstore, and Scoop are runtime package sources for installed tools; `bunx wrangler@latest` is documented for Worker deploy. | `Cargo.toml`, `config/packages.json`, `docs/Distribution.md`, `cloudflare/winmint/README.md` |
| Module/build system | Cargo workspace with `apps/gui` and `crates/winmint-core`; PowerShell dot-sourcing module graph under `src/runtime/image`; Cloudflare Worker configured by Wrangler. | `Cargo.toml`, `src/runtime/image/WinMint.ps1`, `cloudflare/winmint/wrangler.jsonc` |

## 2) Production Frameworks and Dependencies

| Dependency | Version | Role in system | Evidence |
|------------|---------|----------------|----------|
| PowerShell | 7.3+ | Runs the CLI, engine, validation, setup payload authoring, FirstLogon agent, and release tooling. | `README.md`, `WinMint-CLI.ps1`, `tools/validation/Validate.ps1` |
| Windows PowerShell | 5.1 | Bootstrap and staged setup scripts that run inside Windows Setup/first boot contexts. | `winmint.ps1`, `src/runtime/setup/SetupComplete.ps1`, `src/runtime/setup/FirstLogon.ps1` |
| Rust | edition 2021 | GPUI application and typed profile-intent helpers. | `Cargo.toml`, `apps/gui/Cargo.toml`, `crates/winmint-core/Cargo.toml` |
| `gpui` | 0.2.2 | Native GUI framework. | `Cargo.toml`, `apps/gui/Cargo.toml`, `apps/gui/src/main.rs` |
| `gpui-animation` | 0.2.4 | GUI animation wrappers/components. | `Cargo.toml`, `apps/gui/Cargo.toml`, `apps/gui/src/components.rs` |
| `serde` / `serde_json` | 1.0 | Rust JSON serialization for UI intent contracts. | `Cargo.toml`, `crates/winmint-core/src/profile.rs` |
| `embed-resource` | 3.0 | Windows resource embedding for GUI build. | `Cargo.toml`, `apps/gui/build.rs` |
| Cloudflare Workers | compatibility date 2026-04-28 | Serves `winmint.yanai.sh` bootstrap aliases. | `cloudflare/winmint/wrangler.jsonc`, `cloudflare/winmint/src/index.js` |

## 3) Development Toolchain

| Tool | Purpose | Evidence |
|------|---------|----------|
| PSScriptAnalyzer | PowerShell linting with project-specific exclusions. | `PSScriptAnalyzerSettings.psd1`, `tools/validation/Validate.ps1` |
| PowerShell parser checks | Syntax validation for repository PowerShell files. | `tools/validation/Modules/Core.ps1`, `tools/validation/Validate.ps1` |
| Cargo check/test/clippy | Rust type-checking, tests, and linting. | `.cargo/config.toml`, `.github/workflows/ci.yml` |
| JSON schema validation | Build profile, manifest, and agent state contract validation. | `schemas/winmint.buildprofile.schema.json`, `schemas/winmint.buildmanifest.schema.json`, `schemas/winmint.agentstate.schema.json`, `tools/validation/Modules/Schemas.ps1` |
| GitHub Actions | CI validation and release bundle publishing. | `.github/workflows/ci.yml`, `.github/workflows/release.yml` |
| Wrangler | Cloudflare Worker local dev/deploy. | `cloudflare/winmint/README.md`, `cloudflare/winmint/wrangler.jsonc` |

## 4) Key Commands

```powershell
pwsh -NoProfile -File tools\validation\Validate.ps1
pwsh -NoProfile -File tests\contract\Test-Fast.ps1
pwsh -NoProfile -File tests\contract\Test-ProfileInvariants.ps1
cargo check --manifest-path apps/gui/Cargo.toml
cargo test --manifest-path apps/gui/Cargo.toml
pwsh -NoProfile -File WinMint-CLI.ps1 new BuildProfile.json
pwsh -NoProfile -File WinMint-CLI.ps1 build BuildProfile.json -DryRun
pwsh -NoProfile -File tools\release\New-WinMintReleaseBundle.ps1 -Version v0.2.0
```

## 5) Environment and Config

- Config sources: `config/packages.json`, `config/appx-removal.json`, `config/ai-removal.json`, `config/tweaks.json`, `config/autounattend.xml`, `config/release-manifest.json`, `schemas/*.json`.
- Required environment variables: `LOCALAPPDATA` is required by `winmint.ps1`; `WINMINT_ENABLE_EXPERIMENTAL_AI_REMOVAL=1` is required only for aggressive experimental AI removal; other required variables are [TODO].
- Deployment/runtime constraints: Windows 11 host, Administrator for real builds and ISO validation, Windows 11 25H2+ source ISO, ADK `oscdimg.exe`, and DISM new enough for the source image.
- Containers/orchestration: the repo has no container or orchestration config.
- License metadata: documentation states GPL-2.0-or-later, while Cargo workspace metadata states GPL-2.0-only; this is tracked in `CONCERNS.md` as an `[ASK USER]` item.

## 6) Evidence

- `README.md`
- `AGENTS.md`
- `Cargo.toml`
- `THIRD_PARTY_NOTICES.md`
- `apps/gui/Cargo.toml`
- `crates/winmint-core/Cargo.toml`
- `.cargo/config.toml`
- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`
- `PSScriptAnalyzerSettings.psd1`
- `cloudflare/winmint/wrangler.jsonc`
