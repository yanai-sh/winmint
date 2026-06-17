# Coding Conventions

Snapshot note: this document reflects the current development state of the repo as scanned on 2026-06-17. It is an onboarding/audit snapshot, not a continuous authoritative source of truth.

## Core Sections (Required)

### 1) Naming Rules

| Item | Rule | Example | Evidence |
|------|------|---------|----------|
| Files | Public PowerShell launchers use `WinMint-*`; runtime PowerShell files use PascalCase or concern IDs; registry tweak modules use numeric kebab IDs; Rust source files use snake_case modules. | `WinMint-CLI.ps1`, `src/runtime/image/Private/Image/Tweaks/33-edge-policy-minimal.ps1`, `apps/gui/src/bridge.rs` | `rg --files`, `docs/Project-Structure.md` |
| Functions/methods | PowerShell functions use approved verb-style names with `WinMint`, `Agent`, or phase prefixes; Rust functions use snake_case. | `Invoke-WinMintBuildCommand`, `New-WinMintBuildProfile`, `Invoke-WinMintAgentStepRuntime`, `build_ui_intent` | `src/runtime/image/Cli.ps1`, `src/runtime/image/Private/Config/Profile.ps1`, `src/runtime/firstlogon/Agent.Runtime.ps1`, `apps/gui/src/core/src/profile.rs` |
| Types/interfaces | Rust structs/enums use PascalCase. PowerShell structured values are `pscustomobject` / ordered hashtables rather than named classes. | `UiIntent`, `ToolkitIntent`, `DesktopLayersIntent`, `BuildIntent` | `apps/gui/src/core/src/profile.rs`, `apps/gui/src/state.rs` |
| Constants/env vars | Environment variables and JSON schema IDs use uppercase or explicit contract names; Rust constants use `SCREAMING_SNAKE_CASE`. | `WINMINT_ENABLE_EXPERIMENTAL_AI_REMOVAL`, `LOCALAPPDATA`, `SPLASH_STATUS_PICK` | `src/runtime/image/Private/Config/Profile.ps1`, `winmint.ps1`, `apps/gui/src/state.rs` |

### 2) Formatting and Linting

- Formatter: `.editorconfig` specifies UTF-8, final newline, 4-space indentation, LF for most source/config files, CRLF for `.cmd`; no Rust formatter config is checked in.
- Linter: PSScriptAnalyzer is configured in `PSScriptAnalyzerSettings.psd1`, and `tools/validation/Validate.ps1` can run it with `-RunAnalyzer`.
- Most relevant enforced rules: severity `Error`/`Warning`, `PSAvoidLongLines` max 220, `PSUseCompatibleSyntax` target `7.3`; multiple rules are intentionally excluded in `PSScriptAnalyzerSettings.psd1`. Note the lint compat target (`7.3`) lags the actual runtime requirement: module `.psm1` files declare `#Requires -Version 7.6` and `config/release-readiness.json` states `7.6.2+`.
- Run commands: `pwsh -NoProfile -File tools\validation\Validate.ps1 -RunAnalyzer`, `cargo check --manifest-path apps/gui/Cargo.toml`, `cargo test --manifest-path apps/gui/src/core/Cargo.toml`.

### 3) Import and Module Conventions

- Import grouping/order: entrypoints `Import-Module` the `src/runtime/modules/WinMint.<Area>` packages; each `.psm1` dot-sources its ordered area file list from `WinMint.ModuleLoader.ps1` (`Get-WinMintRuntimeModuleFileList`). `src/runtime/image/WinMint.ps1` remains the canonical full ordered dot-source list and a compatibility adapter; tests that need internals dot-source the same runtime families directly.
- Alias vs relative import policy: PowerShell uses repo-root path helpers such as `Get-WinMintPath` after `Core.ps1` is loaded; module loaders resolve the repo root via `Get-WinMintModuleRepositoryRoot`. Rust uses module declarations and direct `use` statements, with `components as ui` in the GPUI app.
- Public exports/barrel policy: PowerShell module packages now carry `.psd1` manifests and `Export-ModuleMember` curated function lists in their `.psm1` bodies (e.g. `WinMint.Engine.psm1`); internal `src/runtime/image` files are still composed by dot-sourcing. Rust `apps/gui/src/core/src/lib.rs` exposes `profile` and `options`.

### 4) Error and Logging Conventions

- Error strategy by layer: entry points commonly set `$ErrorActionPreference = 'Stop'`; validation and tests collect failures into lists and throw at the end; FirstLogon runtime steps carry `FailurePolicy` in `New-WinMintAgentRuntimeStepPlan`, with `profiles` blocking and normal live-user modules advisory.
- Logging style and required context fields: engine console logging flows through `Log`, `LogOK`, `LogWarn`, and manifest facts; FirstLogon writes text logs, JSONL events, command stdout/stderr logs, and `state.json`.
- Sensitive-data redaction rules: local-account passwords can come from `-Password`, `-PasswordPath`, or `-PasswordEnvVar`; direct password use is allowed by project lint exclusions, but explicit redaction/lifecycle rules beyond setup cleanup are `[ASK USER]`.

### 5) Testing Conventions

- Test file naming/location rule: PowerShell contract tests live under `tests/contract/Test-*.ps1`; shared assertions live under `tests/contract/ProfileInvariantTests/*.ps1`; Rust tests are in `#[cfg(test)]` modules.
- Mocking strategy norm: tests use generated fixture profiles, temp directories, string/static assertions, and gitignored fixture roots rather than a separate mocking framework.
- Coverage expectation: no numeric threshold is configured. Keep testing important but pragmatic: contract/static checks for profile and release invariants, Rust unit tests for typed helpers, and targeted VM or dry-run acceptance for risky image/setup behavior.

### 6) Evidence

- `.editorconfig`
- `PSScriptAnalyzerSettings.psd1`
- `src/runtime/modules/WinMint.ModuleLoader.ps1`
- `src/runtime/modules/WinMint.Engine/WinMint.Engine.psm1`
- `src/runtime/image/WinMint.ps1`
- `src/runtime/image/Core.ps1`
- `src/runtime/image/Cli.ps1`
- `apps/gui/src/core/src/options.rs`
- `src/runtime/firstlogon/Agent.Runtime.ps1`
- `tests/contract/Test-ProfileInvariants.ps1`
- `tests/contract/Test-UiContractSpine.ps1`
- `apps/gui/src/core/src/profile.rs`
