# Coding Conventions

## 1) Naming Rules

| Item | Rule | Example | Evidence |
|------|------|---------|----------|
| PowerShell files | PascalCase or domain-prefixed script/module names; registry tweak modules use numeric prefix plus kebab-case id. | `WinMint-CLI.ps1`, `SetupComplete.ps1`, `33-edge-policy-minimal.ps1` | `WinMint-CLI.ps1`, `src/runtime/image/Private/Image/Tweaks/` |
| Rust files | snake_case module files, `main.rs` root, screen modules under `screens/`. | `apps/gui/src/components.rs`, `apps/gui/src/screens/configure.rs` | `apps/gui/src/main.rs` |
| PowerShell functions | Approved verb style with `WinMint`, `Agent`, `Sc`, or feature-specific prefixes. | `Invoke-WinMintIsoPipeline`, `Save-AgentState`, `Invoke-ScEdgeRemoval` | `src/runtime/image/Private/Pipeline.ps1`, `src/runtime/firstlogon/Agent.Runtime.ps1`, `src/runtime/setup/SetupComplete/Edge.ps1` |
| Rust types/functions | Types are PascalCase; functions and fields are snake_case. | `WinMintApp`, `BuildIntent`, `build_ui_intent` | `apps/gui/src/main.rs`, `crates/winmint-core/src/profile.rs` |
| Constants/env vars | Rust constants are uppercase; environment variable gates use uppercase names. | `EXPECTED_INTENT_KEYS`, `WINMINT_ENABLE_EXPERIMENTAL_AI_REMOVAL` | `crates/winmint-core/src/profile.rs`, `src/runtime/image/Private/Config/Profile.ps1` |

## 2) Formatting and Linting

- Formatter: `.editorconfig` sets UTF-8, final newlines, trimmed trailing whitespace, four-space indentation, and LF endings for PowerShell/JSON/XML/YAML/CSS/JS/SVG.
- Linter: `PSScriptAnalyzerSettings.psd1` configures PSScriptAnalyzer.
- Most relevant enforced rules: `PSAvoidLongLines` at 220 chars and `PSUseCompatibleSyntax` targeting PowerShell 7.3.
- Intentional analyzer exclusions: state-changing functions without `ShouldProcess`, internal dot-sourcing, `Write-Host` in entry/validation scripts, empty catch blocks for optional degradation, UTF-8 without BOM, and password/account parameter warnings for the profile contract.
- Rust linting: workspace lint `unsafe_op_in_unsafe_fn = "warn"`; `.cargo/config.toml` maps `cargo lint` to `clippy --workspace --all-targets`.
- Run commands: `pwsh -NoProfile -File tools\validation\Validate.ps1`, `cargo lint`, `cargo checkw`, `cargo testw`.

## 3) Import and Module Conventions

- PowerShell engine modules are dot-sourced explicitly from `src/runtime/image/WinMint.ps1`; sub-files should not be called directly.
- FirstLogon modules are dot-sourced at script scope in `Start-WinMintAgent.ps1` so module functions are visible to the step runner.
- Rust GUI declares local modules in `apps/gui/src/main.rs` and aliases `components` as `ui`.
- Reusable Rust profile intent belongs in `crates/winmint-core`; GUI-only rendering stays in `apps/gui`.
- The current repository has no TypeScript path alias or JavaScript module bundler config.

## 4) Error and Logging Conventions

- Entry scripts set strict/error behavior directly: CLI uses `$ErrorActionPreference = 'Stop'`, `$PSNativeCommandUseErrorActionPreference = $true`, and `Set-StrictMode -Version 2.0`.
- Bootstrap logs through `Write-WinMintBootstrapLog` with timestamp and level.
- Engine progress uses `Write-WinMintProgress`, `Log`, `LogOK`, `LogWarn`, and manifest/report sidecars.
- SetupComplete writes logs under `C:\ProgramData\WinMint\Logs` and aggregates per-script errors in `SetupComplete_errors.log`.
- FirstLogon agent writes `%LOCALAPPDATA%\WinMint\state.json`, log files, command stdout/stderr logs, and JSONL events.
- Sensitive-data convention: build artifacts strip password/autologon state before saving a public profile; setup cleanup deletes Panther unattend files that contain base64-encoded local account passwords.

## 5) Testing Conventions

- PowerShell tests live under `tests/contract` and are named `Test-*.ps1`.
- Contract helper assertions live in `tests/contract/ProfileInvariantTests`.
- Rust tests are colocated in `#[cfg(test)]` modules, e.g. `crates/winmint-core/src/profile.rs`.
- Tests are plain scripts rather than Pester suites; assertions usually collect failures and throw at the end.
- Coverage expectation and coverage tooling are [TODO]; the repo has no coverage threshold config.

## 6) Evidence

- `.editorconfig`
- `PSScriptAnalyzerSettings.psd1`
- `.cargo/config.toml`
- `src/runtime/image/WinMint.ps1`
- `src/runtime/firstlogon/Start-WinMintAgent.ps1`
- `src/runtime/firstlogon/Agent.Runtime.ps1`
- `src/runtime/setup/SetupComplete.ps1`
- `crates/winmint-core/src/profile.rs`
- `tests/contract/Test-Fast.ps1`
