# Architecture

## 1) Architectural Style

- Primary style: layered runtime pipeline. UI, profile/config, image servicing, Windows Setup payloads, FirstLogon, and reporting each have their own boundary.
- Why this classification: the documented flow is `Bootstrap -> UI/CLI -> Engine -> Windows Setup -> FirstLogon Agent`; the engine loads modules in a fixed dot-source order; setup and first-logon scripts are staged artifacts rather than GUI code.
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
5. The ISO pipeline stages the source ISO, converts ESD to WIM if needed, validates DISM and architecture metadata, stages unattend/setup/agent payloads, services WIM images, assembles the ISO, and optionally writes USB media.
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
| Fixed dot-source load order | `src/runtime/image/WinMint.ps1`, `src/runtime/firstlogon/Start-WinMintAgent.ps1` | Keeps script-scoped functions and state available without dynamic imports. |
| Profile as contract | `src/runtime/image/Cli.ps1`, `src/runtime/image/Private/Config/Profile.ps1`, `tools/ui-bridge/New-UiBuildProfile.ps1` | Keeps UI/CLI intent separate from engine execution. |
| JSON contract validation | `schemas/*.json`, `tools/validation/Modules/Schemas.ps1`, `tests/contract/Test-ProfileInvariants.ps1` | Guards profile, manifest, and agent state shapes. |
| Build manifest sidecar | `src/runtime/image/Reports.ps1` | Records what the build did without scraping logs. |
| Step state machine | `src/runtime/firstlogon/Agent.Runtime.ps1`, `schemas/winmint.agentstate.schema.json` | Enables retry/resume and records `running`, `ok`, `failed`, `skipped`, `retryable`, `needsReboot`. |
| Catalog-driven packages | `config/packages.json`, `src/runtime/firstlogon/Agent.Runtime.ps1` | Keeps winget/msstore/Scoop package metadata and architecture handling in one catalog. |
| Per-concern setup modules | `src/runtime/setup/SetupComplete.ps1`, `src/runtime/setup/SetupComplete/*.ps1` | Splits machine-phase setup work while sharing setup profile context. |

## 5) Known Architectural Risks

- Several orchestration files are large enough to slow reviews: local line-count output shows `src/runtime/setup/FirstLogon.Support.ps1` at 1451 lines, `src/runtime/image/Reports.ps1` at 1153 lines, `src/runtime/image/Private/Image/Staging.ps1` at 819 lines, `src/runtime/image/Private/Config/Profile.ps1` at 810 lines, `src/runtime/firstlogon/Agent.Runtime.ps1` at 681 lines, and `apps/gui/src/main.rs` at 632 lines.
- An ignored generated Rust target directory exists at `crates/winmintctl/target`, but `Cargo.toml` lists only `apps/gui` and `crates/winmint-core` as workspace members and no `crates/winmintctl/Cargo.toml` exists. This is a generated-artifact cleanup/intent question, not an active source module.
- The Cloudflare `/cli` wrapper exposes profile-backed bootstrap/headless parameters; future changes should not reintroduce flat configuration flags because `AGENTS.md` and `src/runtime/image/Cli.ps1` make `new` the only configuration verb.

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
