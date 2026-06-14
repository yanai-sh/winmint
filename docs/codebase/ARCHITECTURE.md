# Architecture

## 1) Architectural Style

- Primary style: layered runtime pipeline with separate UI, profile/config, image engine, Windows Setup payloads, FirstLogon agent, and reporting layers.
- Why this classification: entry points and docs repeatedly route work through `Bootstrap -> UI/CLI -> Engine -> Windows Setup -> FirstLogon Agent`; the engine loads modules in a fixed dot-source order; setup and first-logon scripts are staged artifacts rather than GUI code.
- Primary constraints:
  - Windows-native PowerShell execution for servicing and setup.
  - Profile-backed operation: `BuildProfile.json` is the engine input contract.
  - No bundled golden Windows image; source ISO selected by the user is serviced.

## 2) System Flow

```text
WinMint-GUI.ps1 or WinMint-CLI.ps1 -> BuildProfile.json -> src/runtime/image engine -> staged Windows Setup scripts -> FirstLogon agent -> reports/manifests/state
```

1. The GUI writes flat UI intent to `output/gui/ui-intent.json`; the UI bridge converts it to the profile contract with `New-WinMintBuildProfileFromSettings`.
2. The CLI `new` verb also authors a schema v3 build profile; the `build` and `validate` verbs consume a profile with run-specific overrides only.
3. `src/runtime/image/WinMint.ps1` dot-sources core, profile, engine, image, reporting, pipeline, headless, and CLI modules before `Initialize-WinMintEngine` records repository state.
4. `Start-WinMintBuild` validates and normalizes the profile into a build config, writes a sanitized profile artifact, creates reports, initializes a manifest, and calls `Invoke-WinMintIsoPipeline`.
5. The ISO pipeline mounts/stages the source ISO, converts ESD to WIM if needed, validates DISM/architecture metadata, stages unattend/setup/agent payloads, services WIM images, assembles the ISO, and optionally writes USB media.
6. During install, `SetupComplete.ps1` performs machine-phase cleanup and registers `FirstLogon.ps1`; `FirstLogon.ps1` launches `Start-WinMintAgent.ps1`, whose modules update `%LOCALAPPDATA%\WinMint\state.json`.

## 3) Layer/Module Responsibilities

| Layer or module | Owns | Must not own | Evidence |
|-----------------|------|--------------|----------|
| Bootstrap | GitHub release lookup, zip/hash download, local install marker, GUI/headless launch. | Image servicing and profile authoring. | `winmint.ps1`, `docs/Distribution.md` |
| GUI | Source selection, wizard state, visual choices, UI intent JSON. | DISM/WIM servicing. | `apps/gui/src/main.rs`, `apps/gui/README.md` |
| UI bridge | ISO metadata probe, UI intent to build profile conversion, build-from-profile bridge. | Persistent product defaults outside profile helpers. | `tools/ui-bridge/Get-UiIsoMetadata.ps1`, `tools/ui-bridge/New-UiBuildProfile.ps1` |
| CLI | Verb dispatch and command surfaces for `new`, `build`, `validate`, `list`, `clean`. | Parallel flat flag-built build mode. | `WinMint-CLI.ps1`, `src/runtime/image/Cli.ps1` |
| Profile | Schema v3 generation/validation, defaults, keep flags, locale, disk, driver, desktop, WSL, package selections. | Mounting images or installing packages. | `src/runtime/image/Private/Config/Profile.ps1`, `schemas/winmint.buildprofile.schema.json` |
| Engine/pipeline | Source ISO staging, DISM/WIM servicing, drivers, AppX/capability removals, assets, output ISO, USB media. | GUI controls and live-user app installs. | `src/runtime/image/Engine.ps1`, `src/runtime/image/Private/Pipeline.ps1` |
| Setup scripts | SYSTEM/setup-phase cleanup, Windows Update restoration, Edge/OneDrive/AppX/AI cleanup, FirstLogon registration. | User preference prompts. | `src/runtime/setup/SetupComplete.ps1`, `src/runtime/setup/SetupComplete/*.ps1` |
| FirstLogon agent | Package managers, WSL distros, editors, launchers, shell layers, live audit, retry state. | Offline image servicing and disk partitioning. | `src/runtime/firstlogon/Start-WinMintAgent.ps1`, `src/runtime/firstlogon/Modules/` |
| Reports | Build report, manifest, dry-run artifacts, recovery bundle, winget handoff. | Deciding profile behavior. | `src/runtime/image/Reports.ps1` |

## 4) Reused Patterns

| Pattern | Where found | Why it exists |
|---------|-------------|---------------|
| Fixed dot-source load order | `src/runtime/image/WinMint.ps1`, `src/runtime/firstlogon/Start-WinMintAgent.ps1` | Ensures script-scoped functions and state are available without importing modules dynamically. |
| Profile as contract | `src/runtime/image/Cli.ps1`, `src/runtime/image/Private/Config/Profile.ps1`, `tools/ui-bridge/New-UiBuildProfile.ps1` | Keeps UI/CLI intent separate from engine execution. |
| JSON contract validation | `schemas/*.json`, `tools/validation/Modules/Schemas.ps1`, `tests/contract/Test-ProfileInvariants.ps1` | Guards profile, manifest, and agent state shapes. |
| Build manifest sidecar | `src/runtime/image/Reports.ps1` | Records what the build did without scraping logs. |
| Step state machine | `src/runtime/firstlogon/Agent.Runtime.ps1`, `schemas/winmint.agentstate.schema.json` | Enables retry/resume and records `running`, `ok`, `failed`, `skipped`, `retryable`, `needsReboot`. |
| Catalog-driven packages | `config/packages.json`, `src/runtime/firstlogon/Agent.Runtime.ps1` | Centralizes winget/msstore/Scoop package metadata and architecture handling. |
| Per-concern setup modules | `src/runtime/setup/SetupComplete.ps1`, `src/runtime/setup/SetupComplete/*.ps1` | Keeps machine-phase setup concerns separately callable while sharing setup profile context. |

## 5) Known Architectural Risks

- The migration from old `src/engine`, `src/setup`, and `src/agent` paths to `src/runtime/*` is broad and visible in the dirty working tree; stale path assumptions are likely in scripts, docs, tests, or release manifests until validation is run.
- Large orchestration files mix many responsibilities: `src/runtime/setup/FirstLogon.ps1` is 1620 lines, `src/runtime/image/Private/Image/Unattend.ps1` is 959 lines, `src/runtime/image/Reports.ps1` is 939 lines, and `src/runtime/image/Private/Config/Profile.ps1` is 810 lines based on local line-count output.
- The Cloudflare `/cli` wrapper has been reduced to the no-legacy profile-backed bootstrap/headless parameters; future changes should not reintroduce flat configuration flags.

## 6) Evidence

- `AGENTS.md`
- `README.md`
- `WinMint-CLI.ps1`
- `src/runtime/image/WinMint.ps1`
- `src/runtime/image/Cli.ps1`
- `src/runtime/image/Engine.ps1`
- `src/runtime/image/Private/Pipeline.ps1`
- `src/runtime/setup/SetupComplete.ps1`
- `src/runtime/firstlogon/Start-WinMintAgent.ps1`
- `src/runtime/firstlogon/Agent.Runtime.ps1`
