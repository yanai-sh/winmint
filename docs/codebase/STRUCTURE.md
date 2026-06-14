# Codebase Structure

## 1) Top-Level Map

| Path | Purpose | Evidence |
|------|---------|----------|
| `WinMint-CLI.ps1` | Verb-based command-line entry point for profile creation, validation, builds, listing, and cleanup. | `WinMint-CLI.ps1`, `README.md` |
| `WinMint-GUI.ps1` | Launches the packaged or source GPUI front end, with elevation handling. | `WinMint-GUI.ps1`, `apps/gui/README.md` |
| `winmint.ps1` | Remote bootstrapper that downloads a GitHub release zip, verifies hash when present, installs under `%LOCALAPPDATA%`, and launches GUI/headless mode. | `winmint.ps1`, `docs/Distribution.md` |
| `apps/gui/` | Rust/GPUI source for the shipped GUI. | `apps/gui/README.md`, `apps/gui/src/main.rs` |
| `crates/winmint-core/` | Rust helper crate for typed UI/profile intent. | `Cargo.toml`, `crates/winmint-core/src/profile.rs` |
| `src/runtime/image/` | PowerShell image engine, profile handling, DISM/WIM servicing, reports, ISO assembly, and USB media support. | `src/runtime/image/WinMint.ps1`, `src/runtime/image/Engine.ps1`, `src/runtime/image/Private/Pipeline.ps1` |
| `src/runtime/setup/` | Scripts staged into Windows Setup phases, including SetupComplete, FirstLogon, Specialize, and setup modules. | `src/runtime/setup/SetupComplete.ps1`, `src/runtime/setup/FirstLogon.ps1` |
| `src/runtime/firstlogon/` | FirstLogon agent and modules for live-user package, WSL, shell, launcher, and audit work. | `src/runtime/firstlogon/Start-WinMintAgent.ps1`, `src/runtime/firstlogon/Modules/` |
| `config/` | Product policy catalogs and release manifest. | `config/packages.json`, `config/appx-removal.json`, `config/release-manifest.json` |
| `schemas/` | JSON Schema contracts for build profile, build manifest, and agent state. | `schemas/winmint.buildprofile.schema.json`, `schemas/winmint.buildmanifest.schema.json`, `schemas/winmint.agentstate.schema.json` |
| `assets/` | Brand images, runtime payloads, desktop shell presets, default apps, fonts, cursors, wallpaper, and UI preview assets. | `docs/Project-Structure.md`, `THIRD_PARTY_NOTICES.md`, `assets/runtime/` |
| `tools/` | Validation, release, GUI dev, UI bridge, audit, media, and VM tooling. | `tools/validation/Validate.ps1`, `tools/release/New-WinMintReleaseBundle.ps1`, `tools/ui-bridge/` |
| `tests/` | PowerShell contract tests, profile fixtures, and ignored large fixture roots. | `tests/README.md`, `tests/contract/`, `tests/profiles/` |
| `cloudflare/winmint/` | Worker source for the short bootstrap alias, not product runtime. | `cloudflare/winmint/README.md`, `cloudflare/winmint/src/index.js` |
| `.github/workflows/` | CI and release automation. | `.github/workflows/ci.yml`, `.github/workflows/release.yml` |

## 2) Entry Points

- Main runtime entry: `WinMint-CLI.ps1` for command-line builds and profile authoring.
- GUI entry: `WinMint-GUI.ps1`, which either delegates to `tools/gui/Start-GuiDev.ps1` in a source checkout or runs `apps/gui/bin/WinMint-GUI.exe` from a release bundle.
- Bootstrap entry: `winmint.ps1`, served directly or through `cloudflare/winmint/src/index.js`.
- Engine load entry: `src/runtime/image/WinMint.ps1`, which dot-sources the engine modules in order.
- Windows setup entries: `src/runtime/setup/SetupComplete.cmd`, `src/runtime/setup/SetupComplete.ps1`, `src/runtime/setup/FirstLogon.ps1`, `src/runtime/setup/Specialize.ps1`.
- FirstLogon agent entry: `src/runtime/firstlogon/Start-WinMintAgent.ps1`.

## 3) Module Boundaries

| Boundary | What belongs here | What must not be here |
|----------|-------------------|------------------------|
| UI (`apps/gui`, `WinMint-GUI.ps1`, `tools/ui-bridge`) | Guided inputs, UI intent, ISO metadata probe handoff, conversion from GUI intent to `BuildProfile.json`. | DISM servicing and offline registry mutation. |
| Profile/config (`src/runtime/image/Private/Config/Profile.ps1`, schemas) | Defaults, schema v3 shape, validation, compatibility checks, derived build config. | Mounting images, package installation, USB writes. |
| Engine (`src/runtime/image`) | ISO staging, WIM servicing, AppX/capability removal, registry tweaks, setup staging, output ISO, build reports/manifests. | GUI widgets and live-user package installs. |
| Setup scripts (`src/runtime/setup`) | Machine-phase setup during Windows install and first-logon launcher/cleanup. | User-facing wizard state and package source policy decisions. |
| FirstLogon agent (`src/runtime/firstlogon`) | Live-user modules, WSL, editors, shell layers, package managers, retry state. | Offline image servicing and destructive disk choices. |
| Reporting (`src/runtime/image/Reports.ps1`) | Build report, manifest, dry-run artifacts, tweak audit, recovery bundle, winget handoff. | Product business logic decisions. |
| Tooling (`tools`, `tests`) | Development validation, release packaging, VM harnesses, bridge utilities. | Shipped runtime behavior except where tools explicitly stage or validate it. |

## 4) Naming and Organization Rules

- PowerShell files use PascalCase names for scripts/modules and `Verb-WinMint...` style function names, e.g. `Invoke-WinMintIsoPipeline` in `src/runtime/image/Private/Pipeline.ps1`.
- Registry tweak files use numeric prefix plus kebab-case id, e.g. `src/runtime/image/Private/Image/Tweaks/33-edge-policy-minimal.ps1`.
- Rust modules use snake_case file names, with `main.rs` declaring sibling modules and screen submodules under `apps/gui/src/screens/`.
- The Rust workspace is package-based: root `Cargo.toml` lists `apps/gui` and `crates/winmint-core`.
- PowerShell runtime loading is explicit dot-sourcing, especially in `src/runtime/image/WinMint.ps1` and `src/runtime/firstlogon/Start-WinMintAgent.ps1`.

## 5) Evidence

- `docs/Project-Structure.md`
- `WinMint-CLI.ps1`
- `WinMint-GUI.ps1`
- `winmint.ps1`
- `src/runtime/image/WinMint.ps1`
- `src/runtime/firstlogon/Start-WinMintAgent.ps1`
- `apps/gui/src/main.rs`
- `Cargo.toml`
- `tests/README.md`

