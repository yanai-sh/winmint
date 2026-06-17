# Architecture

Snapshot note: this document reflects the current development state of the repo as scanned on 2026-06-18. It is an onboarding/audit snapshot, not a continuous authoritative source of truth.

## Core Sections (Required)

### 1) Architectural Style

- Primary style: layered, contract-first build pipeline.
- Why this classification: repository docs define the flow as `Bootstrap -> UI/CLI -> Engine -> Windows Setup -> FirstLogon Agent`; source files keep these layers in separate entry points and directories; JSON schemas define the contracts between layers.
- Primary constraints:
  - Windows-native PowerShell owns the headless backend and real product work: profile normalization, DISM/WIM servicing, registry hives, Windows Setup, FirstLogon, reports, release tooling, validation, elevation, and host tooling.
  - GPUI/Rust is a frontend layer for intent, previews, and bridge calls into the headless PowerShell engine; it must not own servicing or setup orchestration.
  - Backend composition uses thin PowerShell modules: `WinMint.Bootstrap`, `WinMint.Profile`, and `WinMint.Engine` (which dot-sources `src/runtime/image/WinMint.ps1` as the single canonical runtime load order).
  - `BuildProfile.json`, `BuildManifest.json`, `BuildDelta.json`, and `state.json` are first-class contracts with schemas. `BuildDelta` records currently expose only the fields consumed by GUI review and reports (`id`, `phase`, `kind`, `title`, `userControlled`, `changes`).
  - Public behavior is profile-backed and subtractive by default, with keep flags instead of a broad debloat option matrix.

### 2) System Flow

```text
winmint.ps1 / WinMint-GUI.ps1 / WinMint-CLI.ps1 -> profile authoring/validation -> Start-WinMintBuild -> Invoke-WinMintIsoPipeline -> staged Windows Setup -> Start-WinMintAgent.ps1 -> reports/state
```

1. `winmint.ps1` can download and verify a release bundle, then launch GUI or headless mode; local runs can start `WinMint-GUI.ps1` or `WinMint-CLI.ps1` directly.
2. The Rust GUI writes `output/gui/ui-intent.json` and calls PowerShell bridge scripts; the CLI `new` verb builds a profile from flags.
3. Profile creation and normalization flow through `New-WinMintBuildProfile`, `Assert-WinMintBuildProfile`, schemas, and the backend UI-intent profile authoring module before the engine runs.
4. `Start-WinMintBuild` creates build config, initializes the manifest, preflights prerequisites, and calls the ISO pipeline.
5. The pipeline stages the ISO, selects install images, stamps autounattend/setup/agent profiles, services mounted WIM images, assembles the output ISO, and optionally writes USB media.
6. During Windows install and first logon, setup scripts run machine-phase work and `Start-WinMintAgent.ps1` executes live-user modules while writing `%LOCALAPPDATA%\WinMint\state.json` and command/event logs.

### 3) Layer/Module Responsibilities

| Layer or module | Owns | Must not own | Evidence |
|-----------------|------|--------------|----------|
| Backend module composition | `WinMint.Bootstrap` relaunch, `WinMint.Profile` for UI bridge authoring, `WinMint.Engine` as a thin shim over `WinMint.ps1`. | Per-area module wrappers without consumers. | `src/runtime/modules/WinMint.Engine/WinMint.Engine.psm1`, `src/runtime/image/WinMint.ps1`, `WinMint-CLI.ps1` |
| Bootstrap | Release lookup, asset download, SHA256 verification, ephemeral temp-session launch, elevation/relaunch. | Profile authoring or WIM servicing. | `winmint.ps1`, `src/runtime/modules/WinMint.Bootstrap/WinMint.Bootstrap.psm1`, `docs/Distribution.md` |
| GUI | Source selection, wizard state, previews, intent JSON, PowerShell bridge calls into the headless engine. | DISM/WIM servicing, setup orchestration, live-user package installs. | `apps/gui/src/main.rs`, `apps/gui/src/bridge.rs`, `tools/ui-bridge/New-UiBuildProfile.ps1` |
| CLI verbs | `build`, `new`, `validate`, `list`, `clean`, argument binding, elevation gate. | Parallel flat build-flag execution for `build`. | `WinMint-CLI.ps1`, `src/runtime/image/Cli.ps1` |
| Profile/config | Profile defaults, keep flags, edition/region/update normalization, option-token catalogs, UI-intent profile authoring, validation. | Mounting images or installing packages. | `src/runtime/image/Private/Config/Profile.ps1`, `src/runtime/image/Private/Config/OptionCatalog.ps1`, `src/runtime/image/Private/Config/ProfileAuthoring.ps1`, `schemas/winmint.buildprofile.schema.json` |
| Engine/pipeline | Build config, prerequisites, ISO staging, WIM servicing, offline assets, drivers, final ISO/USB. | GUI state and live-user package installs. | `src/runtime/image/Engine.ps1`, `src/runtime/image/Private/Pipeline.ps1` |
| Audit / delta | Generated backend truth for "what WinMint changes": per-record `id`, `phase`, `kind`, `title`, `userControlled`, and `changes`, written to `WinMint-BuildDelta.json`. | Servicing side effects or UI rendering. | `src/runtime/image/Private/Audit.ps1`, `schemas/winmint.builddelta.schema.json`, `output/WinMint-BuildDelta.json` |
| Reporting | Build manifest lifecycle, dry-run artifacts, tweak audit, recovery bundle, winget handoff, BuildDelta projection into reports. | Primary selection or servicing policy. | `src/runtime/image/Private/Manifest.ps1`, `src/runtime/image/Reports.ps1`, `schemas/winmint.buildmanifest.schema.json` |
| Setup scripts | `Specialize`, `SetupComplete`, default-user, first-logon launch/fallback, machine hygiene. | Offline image servicing. | `src/runtime/setup/SetupComplete.ps1`, `src/runtime/setup/FirstLogon.Runtime.ps1`, `src/runtime/setup/SetupComplete/` |
| FirstLogon agent | Live-user module orchestration, runtime step plan, idempotent step state, command logs, package installs. | Destructive disk operations or WIM servicing. | `src/runtime/firstlogon/Start-WinMintAgent.ps1`, `src/runtime/firstlogon/Agent.Runtime.ps1`, `src/runtime/firstlogon/Modules/` |

### 4) Reused Patterns

| Pattern | Where found | Why it exists |
|---------|-------------|---------------|
| Module import shim over canonical dot-source | `src/runtime/modules/WinMint.Engine/WinMint.Engine.psm1`, `src/runtime/image/WinMint.ps1`, `WinMint-CLI.ps1` | Public entrypoints import `WinMint.Engine`, which loads the full ordered `WinMint.ps1` runtime. `WinMint.Profile` loads a smaller file set for the UI bridge. |
| Ordered dot-source composition | `src/runtime/image/WinMint.ps1`, `tests/contract/Test-ProfileInvariants.ps1` | Canonical full load order for the image engine and contract tests. |
| Contract normalization before side effects | `src/runtime/image/Private/Config/Profile.ps1`, `src/runtime/image/Private/Config/OptionCatalog.ps1`, `src/runtime/image/Private/Config/ProfileAuthoring.ps1`, `tools/ui-bridge/New-UiBuildProfile.ps1`, `src/runtime/image/Engine.ps1` | Converts UI/CLI settings into a stable `BuildProfile.json` before build execution. |
| Run-mode preflight context | `src/runtime/image/Engine.ps1`, `tests/contract/ProfileInvariantTests/ProfileAssertions.ps1` | Keeps build, dry-run, and validate-only policy decisions explicit through `SourceIsoPolicy` and payload/cache requirements. |
| Install plan projection | `src/runtime/image/Private/InstallPlan.ps1`, `src/runtime/image/Private/WslSelection.ps1`, `tests/contract/Test-InstallPlanContract.ps1` | Carries setup profile, agent profile, setup plan, WSL token mapping, and reportable facts as backend output. |
| Setup payload staging | `src/runtime/image/Private/Image/SetupPayloadStaging.ps1`, `src/runtime/image/Private/Image/Unattend.ps1`, `tests/contract/Test-InstallPlanContract.ps1` | Owns setup script/profile/agent/package/desktop asset staging while `Unattend.ps1` stays focused on answer-file mutation. |
| Idempotent step journal/state | `src/runtime/firstlogon/Agent.Runtime.ps1`, `schemas/winmint.agentstate.schema.json` | Allows first-logon retry/resume and prevents optional module failures from blocking all setup. |
| FirstLogon transaction/runtime plans | `src/runtime/setup/FirstLogon.Transaction.ps1`, `src/runtime/setup/FirstLogon.Runtime.ps1`, `src/runtime/firstlogon/Agent.Runtime.ps1`, `tests/contract/Test-FirstLogonTransactionPlan.ps1` | Makes setup phase order, runtime step enablement, failure policy, conditions, and post-step hooks testable through executable plans. |
| Manifest projection | `src/runtime/image/Private/Manifest.ps1`, `src/runtime/image/Reports.ps1`, `schemas/winmint.buildmanifest.schema.json` | Explains build outputs without scraping logs. |
| BuildDelta audit catalog | `src/runtime/image/Private/Audit.ps1`, `schemas/winmint.builddelta.schema.json` | Derives a normalized record of intended changes after profile/install-plan derivation; GUI review, CLI summaries, and reports read `title`/`phase`/`kind`/`userControlled`/`changes` only. |
| Catalog-driven package ownership | `config/packages.json`, `src/runtime/firstlogon/Agent.Runtime.ps1`, `src/runtime/image/Private/Image/Unattend.ps1` | Keeps package source decisions centralized and testable. |
| Catalog-driven UI tokens | `apps/gui/src/core/options.rs`, `apps/gui/src/options.rs`, `src/runtime/image/Private/Config/OptionCatalog.ps1`, `schemas/winmint.uiintent.schema.json` | Keeps serialized UI values aligned across Rust, PowerShell profile validation, schema, GPUI display rows, and bridge tests. |
| Source-controlled registry tweak modules | `src/runtime/image/Private/Image/Tweaks/TweakRegistry.ps1`, `src/runtime/image/Private/Image/Tweaks/*.ps1`, `config/tweaks.json` | Keeps executable tweak logic and public metadata organized by tweak ID. |

### 5) Known Architectural Risks

- Contract duplication risk: UI intent keys and option tokens exist in Rust, a JSON schema, backend profile authoring/catalog modules, the PowerShell bridge adapter, and contract tests; changes must update all of those together.
- Module layer was over-scaffolded and is now trimmed to Bootstrap/Profile/Engine; `WinMint.ps1` remains the single runtime load order inside `WinMint.Engine`.
- Large mixed-responsibility files exist in core paths, including `src/runtime/setup/FirstLogon.Support.ps1`, `src/runtime/image/Private/Manifest.ps1`, `src/runtime/image/Private/Config/Profile.ps1`, `src/runtime/image/Private/Image/Staging.ps1`, and `apps/gui/src/main.rs`.
- UI/backend boundary drift remains possible because Rust/GPUI owns frontend state while PowerShell owns profile generation and build execution; keep bridge contracts and tests updated together.
- Documentation/automation alignment: local `Validate.ps1` skips PSScriptAnalyzer unless `-RunAnalyzer`; CI runs with `-RunAnalyzer`.
- `docs/codebase/` is intentionally a development snapshot and is excluded from release bundles; contributors should not treat it as authoritative over `README.md`, `AGENTS.md`, schemas, or executable tests.

### 6) Evidence

- `AGENTS.md`
- `README.md`
- `docs/Project-Structure.md`
- `WinMint-CLI.ps1`
- `WinMint-GUI.ps1`
- `winmint.ps1`
- `src/runtime/modules/WinMint.ModuleLoader.ps1`
- `src/runtime/modules/WinMint.Engine/WinMint.Engine.psm1`
- `src/runtime/image/WinMint.ps1`
- `src/runtime/image/Engine.ps1`
- `src/runtime/image/Private/Audit.ps1`
- `schemas/winmint.builddelta.schema.json`
- `src/runtime/image/Private/Manifest.ps1`
- `src/runtime/image/Private/InstallPlan.ps1`
- `src/runtime/image/Private/Config/OptionCatalog.ps1`
- `src/runtime/image/Private/Config/ProfileAuthoring.ps1`
- `src/runtime/image/Private/Image/SetupPayloadStaging.ps1`
- `src/runtime/image/Private/WslSelection.ps1`
- `src/runtime/image/Private/Pipeline.ps1`
- `src/runtime/firstlogon/Agent.Runtime.ps1`
- `config/release-manifest.json`
