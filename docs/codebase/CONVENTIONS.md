# Coding Conventions

Snapshot note: updated 2026-07-07. Onboarding/audit snapshot — not a continuous authoritative source.

## Core Sections (Required)

### 1) File Naming

- **PowerShell entry points:** `PascalCase` verb-noun (`WinMint-CLI.ps1`, `WinMint-GUI.ps1`, `Test-ProfileInvariants.ps1`)
- **PowerShell bridge scripts:** `Verb-NounNoun.ps1` (`Get-UiIsoMetadata.ps1`, `New-UiBuildProfile.ps1`, `Start-UiBuildFromProfile.ps1`)
- **PowerShell private modules:** `PascalCase.ps1` (`Profile.ps1`, `TweakRegistry.ps1`, `InstallPlan.ps1`)
- **Tweak modules:** `NN-kebab-id.ps1` with two-digit numeric prefix (`00-hardware-bypass.ps1`, `10-explorer-qol.ps1`)
- **C# setup-shell hosts:** `PascalCase.cs` (`WizardBridge.cs`, `JsonContracts.cs`, `SetupShellHost.cs`)
- **Product docs:** lowercase kebab at repo root for roadmap (`roadmap.md`); PascalCase for runbooks under `docs/` (`VM-Acceptance.md`)

### 2) Function and Variable Naming

- **PowerShell functions:** `Verb-Noun` (`Get-WinMintSelectedRegistryTweaks`, `Initialize-WinMintEngine`, `Add-SmokeFailure`)
- **PowerShell variables:** `$PascalCase` for script-scope state; `$camelCase` acceptable in local scope
- **C# types:** `PascalCase` (`SetupShellStatus`, `RuntimeStateDocument`, `WizardBridge`)
- **JSON contract keys:** camelCase for runtime/guest IPC (`setup-shell-status.json`, `runtime-state.json`); PascalCase for wizard bridge settings until converted to BuildProfile v4
- **Commit style:** Conventional commits with scope (`feat(engine):`, `fix(firstlogon):`, `docs(codebase):`) per `AGENTS.md`

### 3) Linting and Formatting

- **PowerShell:** PSScriptAnalyzer with `PSScriptAnalyzerSettings.psd1`; run via `Validate.ps1 -RunAnalyzer` or CI
- **Intentional PSScriptAnalyzer exclusions** (do not "fix"):
  - `PSUseShouldProcessForStateChangingFunctions`
  - `PSReviewUnusedParameter`
  - `PSAvoidUsingInvokeExpression`
  - `PSAvoidUsingWriteHost`
- **C#:** `dotnet format` on `apps/setup-shell*` projects
- **EditorConfig:** `.editorconfig` present

### 4) Error Handling

- **PowerShell:** `$ErrorActionPreference = 'Stop'` and `$PSNativeCommandUseErrorActionPreference = $true` at entry points
- **C# wizard bridge:** exceptions bubble to WebView2 host; no silent swallow in bridge path
- **FirstLogon modules:** idempotent; optional module failure must not abort entire FirstLogon; `state.json` before/after each step
- **Bootstrap failures:** typed envelope with `operation`, `failureKind`, `reason`, `recoveryGuidance`, `retrySafe`
- **VM acceptance:** orchestrator exits 1 on plumbing fail; writes `acceptance-result.json` with `verdict`, `plumbingVerdict`, `evidenceVerdict`; smoke tier may pass with evidence warnings
- **Setup-shell JSON:** snake_case keys in legacy `setup-shell-control.json` / `setup-shell-status.json`; prefer unified `runtime-state.json` for new readers
- **Setup-shell logging:** native host must emit `host=native` in `SetupShell.log` — asserted by VM smoke evidence and `StaticAssertions.ps1`

### 5) Imports and Module Loading

- **PowerShell engine:** dot-source only via `src/runtime/image/WinMint.ps1`
- **C# hosts:** small focused projects under `apps/setup-shell/` and `apps/setup-shell-web/`
- **No external PowerShell module deps** beyond PowerShell 7 and Windows ADK tooling

### 6) Comments

- Self-documenting naming preferred; `ponytail:` comments mark intentional shortcuts with known ceiling and upgrade path (see `src/runtime/firstlogon/`, `src/runtime/setup/`)
- PSScriptAnalyzer exclusions documented in `AGENTS.md`

### 7) Evidence

- `PSScriptAnalyzerSettings.psd1`
- `.editorconfig`
- `apps/setup-shell-web/WizardBridge.cs`, `apps/setup-shell/JsonContracts.cs`
- `AGENTS.md`
- `schemas/winmint.runtimestate.schema.json`, `schemas/winmint.setupshellstatus.schema.json`
- `tools/vm/lib/*.ps1`
