# Codebase Structure

Snapshot note: this document reflects the current development state of the repo as scanned on 2026-06-18. It is an onboarding/audit snapshot, not a continuous authoritative source of truth.

## Core Sections (Required)

### 1) Top-Level Map

| Path | Purpose | Evidence |
|------|---------|----------|
| `WinMint-CLI.ps1` | Public verb-based CLI dispatcher. | `WinMint-CLI.ps1`, `src/runtime/image/Cli.ps1` |
| `WinMint-GUI.ps1` | Public launcher for the GPUI app, with elevation and source/dev binary resolution. | `WinMint-GUI.ps1`, `tools/gui/Start-GuiDev.ps1` |
| `winmint.ps1` | Remote bootstrapper that downloads, verifies, installs, and launches a release bundle. | `winmint.ps1`, `docs/Distribution.md` |
| `src/runtime/modules/` | Thin PowerShell module shims: `WinMint.Bootstrap` (elevation/relaunch), `WinMint.Profile` (UI bridge profile authoring), and `WinMint.Engine` (dot-sources `src/runtime/image/WinMint.ps1`). `WinMint.ModuleLoader.ps1` maps `Profile` to a smaller file set. | `src/runtime/modules/WinMint.Engine/WinMint.Engine.psm1`, `WinMint-CLI.ps1` |
| `src/runtime/image/` | Shipped image engine, profile normalization, option-token catalogs, DISM/WIM servicing, media/USB output, reporting, and the `BuildDelta` audit pipeline. `WinMint.ps1` is the canonical ordered dot-source root loaded by `WinMint.Engine`. | `src/runtime/image/Engine.ps1`, `src/runtime/image/Private/Pipeline.ps1`, `src/runtime/image/Private/Audit.ps1`, `src/runtime/image/WinMint.ps1` |
| `src/runtime/setup/` | Scripts staged into Windows Setup phases (`Specialize`, `SetupComplete`, `FirstLogon`, setup modules). | `src/runtime/setup/SetupComplete.ps1`, `src/runtime/setup/FirstLogon.ps1`, `src/runtime/setup/Specialize.ps1` |
| `src/runtime/firstlogon/` | Live-user FirstLogon agent, retry state, package installs, WSL/editor/shell modules, and console output. | `src/runtime/firstlogon/Start-WinMintAgent.ps1`, `src/runtime/firstlogon/Agent.Runtime.ps1`, `src/runtime/firstlogon/Modules/` |
| `apps/gui/` | Main Rust GPUI frontend, wizard, previews, PowerShell bridge caller, and in-crate UI intent/options helpers (`src/core/`). | `apps/gui/Cargo.toml`, `apps/gui/src/main.rs`, `apps/gui/src/bridge.rs`, `apps/gui/src/core/profile.rs` |
| `tools/` | Developer automation for validation, release bundling, GUI bridge, VM tests, audits, and utilities. | `tools/validation/Validate.ps1`, `tools/release/New-WinMintReleaseBundle.ps1`, `tools/ui-bridge/New-UiBuildProfile.ps1`, `tools/vm/Build-And-TestVm.ps1` |
| `tests/` | Contract tests, profile fixtures, and ignored large fixture roots. | `tests/README.md`, `tests/contract/Test-Fast.ps1`, `tests/profiles/hyper-v-install-arm64.json` |
| `config/` | Product catalogs, release manifest, release-readiness/hardware-acceptance/Surface-driver policy, unattended setup template, and tracked build-profile samples. | `config/packages.json`, `config/release-manifest.json`, `config/release-readiness.json`, `config/hardware-acceptance.json`, `config/surface-drivers.json`, `config/build-profiles/`, `config/autounattend.xml` |
| `schemas/` | JSON schemas for profile, manifest, build delta, agent state, and UI intent contracts. | `schemas/winmint.buildprofile.schema.json`, `schemas/winmint.buildmanifest.schema.json`, `schemas/winmint.builddelta.schema.json`, `schemas/winmint.agentstate.schema.json`, `schemas/winmint.uiintent.schema.json` |
| `assets/` | Brand/UI assets plus runtime payloads staged into images or first-logon setup. | `assets/brand/`, `assets/runtime/`, `assets/ui/`, `docs/Project-Structure.md` |
| `cloudflare/winmint/` | Distribution alias Worker, outside the WinMint runtime bundle. | `cloudflare/winmint/src/index.js`, `cloudflare/winmint/wrangler.jsonc`, `docs/Distribution.md` |
| `output/`, `dist/`, `target/`, `node_modules/`, `temp/` | Generated or local dependency/build artifacts; not source layout. | `.gitignore`, `docs/Project-Structure.md`, `tools/validation/Modules/Core.ps1` |

### 2) Entry Points

- Main runtime entry: `WinMint-CLI.ps1` for CLI builds and `WinMint-GUI.ps1` for the shipped GUI launcher.
- Secondary entry points: `winmint.ps1` remote bootstrapper, `src/runtime/firstlogon/Start-WinMintAgent.ps1`, `src/runtime/setup/SetupComplete.ps1`, `src/runtime/setup/FirstLogon.ps1`, `apps/gui/src/main.rs`, `cloudflare/winmint/src/index.js`.
- How entry is selected: `WinMint-CLI.ps1` first `Import-Module`s `WinMint.Bootstrap` (elevation/relaunch), then `WinMint.Engine` (`Initialize-WinMintEngine`), then dispatches the first positional token to verb functions via `Invoke-WinMintVerbFunction` (verb bodies live in `src/runtime/image/Cli.ps1`); `WinMint-GUI.ps1` starts `tools/gui/Start-GuiDev.ps1` from source or the packaged GUI binary; `winmint.ps1` selects GUI/headless mode with `-Mode`, `-Gui`, or `-Headless`.

### 3) Module Boundaries

| Boundary | What belongs here | What must not be here |
|----------|-------------------|------------------------|
| UI (`apps/gui`, `WinMint-GUI.ps1`) | Guided inputs, previews, `ui-intent.json`, bridge calls into the headless PowerShell engine. | DISM servicing, registry hive edits, Windows Setup orchestration, live-user package installs. |
| Profile/config (`src/runtime/image/Private/Config/Profile.ps1`, `src/runtime/image/Private/Config/OptionCatalog.ps1`, `src/runtime/image/Private/Config/ProfileAuthoring.ps1`, schemas) | Defaults, derived settings, option-token catalogs, schema/profile validation, CLI/GUI intent normalization and persistence. | Image mounting, package installation side effects. |
| Engine (`src/runtime/image`) | ISO staging, WIM servicing, driver injection, staged setup files, reports, USB media output. | GUI controls or live-user package installs. |
| Setup scripts (`src/runtime/setup`) | Machine-phase setup during Windows install. | User-facing selection prompts or offline image servicing. |
| FirstLogon agent (`src/runtime/firstlogon`) | Live-user package managers, WSL, editors, shell layers, retry state. | Offline WIM servicing or destructive disk choices. |
| Reports (`src/runtime/image/Private/Manifest.ps1`, `src/runtime/image/Reports.ps1`) | Manifest lifecycle and report artifacts, tweak audit artifacts, recovery bundle output. | Primary business decisions. |
| Tools/tests (`tools`, `tests`) | Repo validation, release packaging, VM/audit harnesses, contract tests. | Shipped runtime behavior unless explicitly included by release manifest. |

### 4) Naming and Organization Rules

- File naming pattern: PowerShell entry/module files mostly use PascalCase or descriptive kebab-like tweak IDs, for example `WinMint-CLI.ps1`, `SetupComplete.ps1`, `Private/Image/Tweaks/33-edge-policy-minimal.ps1`; Rust modules use snake_case filenames, for example `apps/gui/src/main.rs` and `apps/gui/src/core/profile.rs`.
- Directory organization pattern: layer-based runtime split (`modules`, `image`, `setup`, `firstlogon`) plus domain subdirectories inside those layers (`Private/Image/Tweaks`, `Modules`, `SetupComplete`). Module packages under `src/runtime/modules/` use one folder per module with a paired `WinMint.<Area>.psd1` manifest and `WinMint.<Area>.psm1` body.
- Import aliasing or path conventions: public entrypoints `Import-Module` `WinMint.Bootstrap` and `WinMint.Engine`; `WinMint.Engine` dot-sources `src/runtime/image/WinMint.ps1`. `WinMint.Profile` dot-sources a smaller authoring file set via `WinMint.ModuleLoader.ps1`. GUI Rust aliases `components` as `ui`; shared serialized UI values come from `apps/gui/src/core/options.rs` on the Rust side and `Private/Config/OptionCatalog.ps1` on the PowerShell side; GPUI display rows adapt those values from `apps/gui/src/options.rs`.

### 5) Evidence

- `docs/Project-Structure.md`
- `AGENTS.md`
- `WinMint-CLI.ps1`
- `WinMint-GUI.ps1`
- `winmint.ps1`
- `src/runtime/modules/WinMint.ModuleLoader.ps1`
- `src/runtime/image/WinMint.ps1`
- `apps/gui/src/main.rs`
- `tools/validation/Modules/Repository.ps1`
- `config/release-manifest.json`
