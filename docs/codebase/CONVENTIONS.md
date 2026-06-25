# Coding Conventions

Snapshot note: updated 2026-06-25. Onboarding/audit snapshot — not a continuous authoritative source.

## Core Sections (Required)

### 1) File Naming

- **PowerShell entry points:** `PascalCase` verb-noun (`WinMint-CLI.ps1`, `WinMint-GUI.ps1`, `Test-ProfileInvariants.ps1`)
- **PowerShell bridge scripts:** `Verb-NounNoun.ps1` (`Get-UiIsoMetadata.ps1`, `New-UiBuildProfile.ps1`, `Start-UiBuildFromProfile.ps1`)
- **PowerShell private modules:** `PascalCase.ps1` (`Profile.ps1`, `TweakRegistry.ps1`, `InstallPlan.ps1`)
- **Tweak modules:** `NN-kebab-id.ps1` with two-digit numeric prefix establishing execution order (`00-hardware-bypass.ps1`, `10-explorer-qol.ps1`)
- **Rust modules:** `snake_case.rs` (`bridge.rs`, `state.rs`, `components.rs`, `intent.rs`)

### 2) Function and Variable Naming

- **PowerShell functions:** `Verb-Noun` (`Get-WinMintSelectedRegistryTweaks`, `Initialize-WinMintEngine`, `Add-SmokeFailure`)
- **PowerShell variables:** `$PascalCase` for script-scope state (`$WinMintRepositoryRoot`, `$DryRun`); `$camelCase` acceptable in local scope
- **Rust types/structs:** `PascalCase` (`WinMintApp`, `BridgeBuildResult`, `SourceProbeState`)
- **Rust functions/methods:** `snake_case` (`probe_source`, `write_intent`, `architecture_hint`)
- **Rust fields:** `snake_case` (`iso_path`, `build_run`, `spinner_phase`)
- **JSON contract keys:** PascalCase — enforced by `serde(rename_all = "PascalCase")` in all bridge deserializer structs

### 3) Linting and Formatting

- **PowerShell:** PSScriptAnalyzer with `PSScriptAnalyzerSettings.psd1`; run via `Validate.ps1 -RunAnalyzer` or CI
- **Intentional PSScriptAnalyzer exclusions** (do not "fix" these):
  - `PSUseShouldProcessForStateChangingFunctions` — UI/build helpers don't need `-WhatIf`
  - `PSReviewUnusedParameter` — `DryRun` param used indirectly via `CmdletBinding`
  - `PSAvoidUsingInvokeExpression` — dot-sourcing internal blocks is the load pattern
  - `PSAvoidUsingWriteHost` — entry points and validation helpers report directly to console
- **Rust:** standard `cargo fmt` / `cargo clippy` (not explicitly configured beyond workspace lints); `unsafe_op_in_unsafe_fn = "warn"` enforced workspace-wide
- **EditorConfig:** `.editorconfig` present for cross-editor whitespace consistency

### 4) Error Handling

- **PowerShell:** `$ErrorActionPreference = 'Stop'` and `$PSNativeCommandUseErrorActionPreference = $true` at the top of every entry point; errors propagate as terminating exceptions
- **Rust bridge:** bridge functions return `Result<T, String>` (error as plain string); GUI maps errors to `build_run.status` SharedString for display — no panics in the bridge path
- **FirstLogon modules:** each module must be idempotent; a failed optional module must not abort the entire FirstLogon; `state.json` is written before and after each step
- **Bootstrap failures:** `winmint.ps1` uses a typed failure envelope with `operation`, `failureKind`, `reason`, `recoveryGuidance`, `retrySafe` fields

### 5) Imports and Module Loading

- **PowerShell:** dot-source only via `src/runtime/image/WinMint.ps1`; never call sub-files directly from external callers
- **Rust:** `mod` declarations in `main.rs`; `use components as ui;` alias for call-site brevity; no barrel re-export pattern
- **No external PowerShell module deps** beyond what ships with PowerShell 7 and the Windows ADK

### 6) Comments

- Code is primarily self-documenting through naming; inline comments explain non-obvious invariants or platform workarounds
- Intentional PSScriptAnalyzer suppressions documented in `AGENTS.md` rather than inline suppression comments
- Rust: doc comments (`///`) on public-facing items; module-level `//!` on `bridge.rs` explains its purpose

### 7) Evidence

- `PSScriptAnalyzerSettings.psd1` — linter settings
- `.editorconfig` — formatting rules
- `apps/gui/src/main.rs` — naming conventions in Rust
- `apps/gui/src/bridge.rs` — error handling and JSON conventions
- `AGENTS.md` — PSScriptAnalyzer exclusions, dot-source rule
- `src/runtime/image/WinMint.ps1` — `$ErrorActionPreference = 'Stop'` pattern
