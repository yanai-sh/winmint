# Codebase Structure

Snapshot note: this document reflects the current development state of the repo. It is an onboarding/audit snapshot, not a continuous authoritative source of truth.

## Core Sections (Required)

### 1) Top-Level Map

| Path | Purpose | Evidence |
|------|---------|----------|
| `WinMint-CLI.ps1` | Public verb-based CLI dispatcher. | `WinMint-CLI.ps1`, `src/runtime/image/Cli.ps1` |
| `WinMint-GUI.ps1` | Public launcher for the GPUI app, with elevation and source/dev binary resolution. | `WinMint-GUI.ps1`, `tools/gui/Start-GuiDev.ps1` |
| `winmint.ps1` | Remote bootstrapper that downloads, verifies, installs, and launches a release bundle. | `winmint.ps1`, `docs/Distribution.md` |
| `src/runtime/image/` | Shipped image engine, profile normalization, DISM/WIM servicing, media/USB output, and reporting. | `src/runtime/image/WinMint.ps1`, `src/runtime/image/Engine.ps1`, `src/runtime/image/Private/Pipeline.ps1` |
| `src/runtime/setup/` | Scripts staged into Windows Setup phases (`Specialize`, `SetupComplete`, `FirstLogon`, setup modules). | `src/runtime/setup/SetupComplete.ps1`, `src/runtime/setup/FirstLogon.ps1`, `src/runtime/setup/Specialize.ps1` |
| `src/runtime/firstlogon/` | Live-user FirstLogon agent, retry state, package installs, WSL/editor/shell modules, and console output. | `src/runtime/firstlogon/Start-WinMintAgent.ps1`, `src/runtime/firstlogon/Agent.Runtime.ps1`, `src/runtime/firstlogon/Modules/` |
| `apps/gui/` | Main Rust GPUI frontend, wizard, previews, and PowerShell bridge caller. | `apps/gui/Cargo.toml`, `apps/gui/src/main.rs`, `apps/gui/src/bridge.rs` |
| `apps/firstlogon-gui/` | Rust GPUI status/demo surface for first-logon progress. | `apps/firstlogon-gui/Cargo.toml`, `apps/firstlogon-gui/src/main.rs` |
| `crates/winmint-core/` | Rust shared UI intent/profile helper crate. | `crates/winmint-core/Cargo.toml`, `crates/winmint-core/src/profile.rs` |
| `tools/` | Developer automation for validation, release bundling, GUI bridge, VM tests, audits, and utilities. | `tools/validation/Validate.ps1`, `tools/release/New-WinMintReleaseBundle.ps1`, `tools/ui-bridge/New-UiBuildProfile.ps1`, `tools/vm/Build-And-TestVm.ps1` |
| `tests/` | Contract tests, profile fixtures, and ignored large fixture roots. | `tests/README.md`, `tests/contract/Test-Fast.ps1`, `tests/profiles/hyper-v-install-arm64.json` |
| `config/` | Product catalogs, release manifest, unattended setup template, and build-profile samples. | `config/packages.json`, `config/release-manifest.json`, `config/autounattend.xml` |
| `schemas/` | JSON schemas for profile, manifest, agent state, and UI intent contracts. | `schemas/winmint.buildprofile.schema.json`, `schemas/winmint.buildmanifest.schema.json`, `schemas/winmint.agentstate.schema.json`, `schemas/winmint.uiintent.schema.json` |
| `assets/` | Brand/UI assets plus runtime payloads staged into images or first-logon setup. | `assets/brand/`, `assets/runtime/`, `assets/ui/`, `docs/Project-Structure.md` |
| `cloudflare/winmint/` | Distribution alias Worker, outside the WinMint runtime bundle. | `cloudflare/winmint/src/index.js`, `cloudflare/winmint/wrangler.jsonc`, `docs/Distribution.md` |

### 2) Entry Points

- Main runtime entry: `WinMint-CLI.ps1` for CLI builds and `WinMint-GUI.ps1` for the shipped GUI launcher.
- Secondary entry points: `winmint.ps1` remote bootstrapper, `src/runtime/firstlogon/Start-WinMintAgent.ps1`, `src/runtime/setup/SetupComplete.ps1`, `src/runtime/setup/FirstLogon.ps1`, `apps/gui/src/main.rs`, `apps/firstlogon-gui/src/main.rs`, `cloudflare/winmint/src/index.js`.
- How entry is selected: `WinMint-CLI.ps1` dispatches the first positional token to verbs in `src/runtime/image/Cli.ps1`; `WinMint-GUI.ps1` starts `tools/gui/Start-GuiDev.ps1` from source or the packaged GUI binary; `winmint.ps1` selects GUI/headless mode with `-Mode`, `-Gui`, or `-Headless`.

### 3) Module Boundaries

| Boundary | What belongs here | What must not be here |
|----------|-------------------|------------------------|
| UI (`apps/gui`, `WinMint-GUI.ps1`) | Guided inputs, previews, `ui-intent.json`, bridge calls into the headless PowerShell engine. | DISM servicing, registry hive edits, Windows Setup orchestration, live-user package installs. |
| Profile/config (`src/runtime/image/Private/Config/Profile.ps1`, schemas) | Defaults, derived settings, schema/profile validation, CLI/GUI intent normalization. | Image mounting, package installation side effects. |
| Engine (`src/runtime/image`) | ISO staging, WIM servicing, driver injection, staged setup files, reports, USB media output. | GUI controls or live-user package installs. |
| Setup scripts (`src/runtime/setup`) | Machine-phase setup during Windows install. | User-facing selection prompts or offline image servicing. |
| FirstLogon agent (`src/runtime/firstlogon`) | Live-user package managers, WSL, editors, shell layers, retry state. | Offline WIM servicing or destructive disk choices. |
| Reports (`src/runtime/image/Reports.ps1`) | Manifest/report artifacts, tweak audit artifacts, recovery bundle output. | Primary business decisions. |
| Tools/tests (`tools`, `tests`) | Repo validation, release packaging, VM/audit harnesses, contract tests. | Shipped runtime behavior unless explicitly included by release manifest. |

### 4) Naming and Organization Rules

- File naming pattern: PowerShell entry/module files mostly use PascalCase or descriptive kebab-like tweak IDs, for example `WinMint-CLI.ps1`, `SetupComplete.ps1`, `Private/Image/Tweaks/33-edge-policy-minimal.ps1`; Rust modules use snake_case filenames, for example `apps/gui/src/main.rs` and `crates/winmint-core/src/profile.rs`.
- Directory organization pattern: layer-based runtime split (`image`, `setup`, `firstlogon`) plus domain subdirectories inside those layers (`Private/Image/Tweaks`, `Modules`, `SetupComplete`).
- Import aliasing or path conventions: PowerShell runtime modules are dot-sourced in explicit order from `src/runtime/image/WinMint.ps1`; GUI Rust aliases `components` as `ui`; repo paths should resolve through `Get-WinMintPath` in `src/runtime/image/Core.ps1` when available.

### 5) Evidence

- `docs/Project-Structure.md`
- `AGENTS.md`
- `WinMint-CLI.ps1`
- `WinMint-GUI.ps1`
- `winmint.ps1`
- `src/runtime/image/WinMint.ps1`
- `apps/gui/src/main.rs`
- `tools/validation/Modules/Repository.ps1`
- `config/release-manifest.json`
