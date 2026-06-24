# WinMint — Agent context

Windows 11 ISO builder. Windows-native. Requires `pwsh` 7.6.2+ for backend/runtime scripts.
Development usually happens from WSL or an editor, but all project scripts execute on Windows.

`AGENTS.md` is the compact implementation contract for coding agents. User-facing product behavior, usage examples, and rationale belong in `README.md`.

The core design rule: **UI creates intent. Engine performs work. Reports explain work. FirstLogon finishes live-user setup.**

PowerShell owns the backend and all real product work: profile normalization, ISO/WIM servicing, setup payloads, FirstLogon, reports, release tooling, and validation tooling. The actual build logic must stay headless. GPUI/Rust is a frontend layer that creates intent, previews choices, and invokes the headless PowerShell engine; it must not own servicing, setup orchestration, offline registry edits, or live-user package installation.

Backend composition uses thin PowerShell modules under `src/runtime/modules/`. Public entrypoints import `WinMint.Bootstrap` (elevation/relaunch), `WinMint.Profile` (profile authoring for the UI bridge), and `WinMint.Engine` (dot-sources `src/runtime/image/WinMint.ps1` as the single canonical runtime load order). Do not add parallel per-area module wrappers unless they have real consumers.

## Product stance (opinionated)

- **User ISO is the truth.** There is no pinned “golden” Windows build inside the repo. Whatever **source ISO** the user picks (subject to documented minimums, e.g. Windows 11 **25H2+** in `README.md`) is the version DISM services. AppX prefixes and registry stamps are **best-effort** against common SKUs; odd OEM bundles may need follow-up outside the wizard.
- **Home-first target.** The primary product target is Windows 11 Home / Home Single Language / en-US. Generated profiles use schema v3, default visible region values of en-US / GeoID 244, and default fixed-edition builds to standard `Windows 11 Home`. Do not silently fall back to Pro when a fixed Home image is missing.
- **Source choice stays simple.** The user-provided official Microsoft ISO is the source of truth. WinMint does not expose UUP Dump selection or conversion as a public product choice. Do not bundle Microsoft payloads or silently download them; require only a high-level consent/automation acknowledgement when network download or conversion is needed.
- **No debloat/performance wizard flags.** Defaults live in engine/profile/setup scripts only—one coherent WinMint posture, not a choice matrix.
- **Subtractive default + opt-in "keep" flags, not granular toggles.** The default build removes full serviceable AI, Xbox/gaming, and the developer tweaks are folded in as baseline. Edge browser noise/AI/promo policy is applied by default. `-KeepEdge` keeps the browser installed and debloated; without `-KeepEdge`, removal intent is serviced through the normal supported Edge app uninstaller exposed by DMA setup. Opt-in keep flags suppress one domain each: `-KeepGaming` (keep Xbox/Game Bar + gaming-performance tweaks), `-KeepCopilot` (keep all Copilot+ AI features *except Recall*, which is always removed), `-KeepEdge` (keep Edge browser; policies still apply). `-DesktopUI` is still an additive shell selection; `-Install windhawk,yasb,komorebi` picks window-manager tooling; editors stay opt-in while WSL2 is always enabled and distro selection remains explicit. WinMint is WSL-first, but Linux distro installs remain explicit. The baseline also uses XDG-style dotfolders for config/data/state/cache, with a temp-backed runtime directory, so XDG-aware tools avoid `AppData` by default. Dev Drive is not a WinMint default; if the user wants it, that is a separate user-managed setup step. There is no `Developer`/`CopilotPlus` group and no `profileGroups`/`setupOption` vocabulary — the keep flags are the only profile dimension.
- **Profile is the source of truth; the CLI is verb-based.** `WinMint-CLI.ps1` dispatches verbs (`build`/`new`/`validate`/`list`/`clean`; no verb opens the interactive wizard). Configuration flags (`-Edition`, `-Keep*`, `-Install`, `-Dma On|Off`, `-Location On|Off`, `-GenericKey Auto|On|Off`, locales, drivers) live only on `new`, which authors a profile. `build <profile>` and `validate <profile>` consume a profile and accept only run-specific overrides (`-SourceIso`, `-DryRun`, `-WriteUsb -Disk N`, `-Yes`, `-Json`, `-Quiet`, `-AllowElevate`, and the image-quality overrides `-Compression Max|Fast|None` / `-FastImage`). Do not reintroduce flag-built builds or a parallel flat flag block. Image quality is a run override, not a profile field: `-Compression Max` (default) recompresses hard and runs WinSxS `StartComponentCleanup` for a lean release ISO; `Fast`/`None` skip the cleanup for fast test builds; `-FastImage` is the test-quality preset (`None` + no cleanup). The manifest records `servicing.exportCompression` and `servicing.componentCleanup`.
- **DMA interop is default-on, fixed-region, and restore-first.** Unless explicitly disabled with `-Dma Off` / `tweaks.dmaInterop = false`, Windows Setup uses Ireland / `en-IE` / GeoID `68` internally. Do not expose an EEA country picker. FirstLogon must restore the user-configured visible region, locale, time zone, and location-services posture before OneDrive cleanup, optional agent modules, shell setup, WSL/editors, or live audit.
- **Local accounts require a password.** A pre-created passwordless local account still triggers the Windows 11 24H2/25H2 OOBE "Create a password" page, which blocks an otherwise-unattended install (omitting the `<Password>` element does not suppress it). The build preflight fails a real `-AccountMode Local` build with no password; supply one via `-Password`/`-PasswordPath`/`-PasswordEnvVar`, or use `-AccountMode MicrosoftOobe` for interactive account setup. For fully unattended local-account builds, the OOBE network page is hidden and the profile-computer-name is used directly. Dry runs are exempt (they generate artifacts without installing).
- **Laptop defaults are intentional.** Location services default on; `-Location Off` is the explicit opt-out and should also block Find My Device. Storage Sense safe cleanup and Modern Standby network-off policy are default-on, with Downloads cleanup disabled.
- **Power plans are explicit and non-destructive.** Generated profiles default to `target.powerPlan = Balanced`; `EnergySaver`, `HighPerformance`, and `UltimatePerformance` are explicit profile selections. SetupComplete activates the selected plan on laptops or desktops without deleting other Windows/OEM schemes. Desktop hibernation disable remains form-factor-gated and must not apply to laptops.
- **No maintenance payload.** WinMint must not leave a maintenance scheduled task, background service, or maintenance script behind on the installed system. Post-update drift is the user’s responsibility after installation; maintenance experiments do not belong under shipped runtime/setup folders.
- **Destructive disk behavior is explicit.** Disk modes are `Manual`, `AutoWipeDisk0`, and `DualBootReserved`. Dual-boot mode reserves Windows space using one of `WindowsHeavy`, `Balanced`, `EvenSplit`, or `LinuxHeavy`, and leaves the rest unallocated for another OS.
- **AI removal is serviceable by default.** Public behavior must use supported AppX, optional-feature, registry-policy, service-disable, task-disable, and audit paths. TrustedInstaller ownership tricks, CBS metadata deletion, fake update payloads, `IntegratedServicesRegionPolicySet.json` patches, and maintenance tasks are internal-only research territory and require the `AggressiveExperimental` gate.

## Commands

```powershell
# Validate syntax (PSScriptAnalyzer runs in CI and via -RunAnalyzer locally)
pwsh -NoProfile -File tools\validation\Validate.ps1
pwsh -NoProfile -File tools\validation\Validate.ps1 -RunAnalyzer

# Smoke-test profile invariants (no ISO or Windows required)
pwsh -NoProfile -File tests\contract\Test-ProfileInvariants.ps1

# Author a profile, then dry-run a build from it (no ISO required to author)
pwsh -NoProfile -File WinMint-CLI.ps1 new BuildProfile.json
pwsh -NoProfile -File WinMint-CLI.ps1 build BuildProfile.json -DryRun

# UI build
pwsh -NoProfile -File WinMint-GUI.ps1

# Release bundle (outputs to dist\)
pwsh -NoProfile -File tools\release\New-WinMintReleaseBundle.ps1 -Version v0.2.0
```

For automation tests: leave the password fields blank (passwordless local
account). The wizard supports passwordless and the Identity preview shows a
"Passwordless" pill.

## Architecture

```
Bootstrap → UI/CLI → Engine → Windows Setup → FirstLogon Agent
```

## VM Test Invariant

Hyper-V VM acceptance profiles are always **Windows 11 Pro** with the Pro generic
key because Enhanced Session testing depends on Pro. Do not repoint
`tests/profiles/hyper-v-install-arm64.json` at a Home-only ISO or change it to
Home. If a pre-updated VM ISO is needed, build a separate pre-updated **Pro** ISO
from Pro-capable source media.

| Layer | Entry point | Purpose |
|-------|-------------|---------|
| CLI | `WinMint-CLI.ps1` | Headless verb dispatcher (`build`/`new`/`validate`/`list`/`clean`; no verb = interactive wizard). Verb functions live in `src/runtime/image/Cli.ps1` and delegate to the engine |
| Engine | `src/runtime/image/WinMint.ps1` | Dot-sources all private modules; owns DISM/WIM servicing |
| UI | `WinMint-GUI.ps1`; `apps/gui/` | GPUI is the only shipped GUI and is frontend-only: guided input, previews, validation messages, and bridge calls into the headless PowerShell engine. Prefer native GPUI APIs and platform abstractions over external GUI/tooling workarounds; for example, use `App::prompt_for_paths` with `PathPromptOptions` for file/folder selection instead of `rfd`, WinForms/WPF shells, or PowerShell picker helpers. The GPUI app uses `gpui-animation` for state-driven hover transitions; interactive wrappers must use `AnimatedWrapper::on_click` (not the inner `div`’s `on_click`) so the animation hook is not overwritten. Shared controls live in `apps/gui/src/components.rs` (aliased `ui::`) as stateless `pub fn` builders — keep them in that single file. Split into a `components/` directory (thematic submodules re-exported from `mod.rs` so `ui::*` call sites are unchanged) only once a component grows internal state and becomes a `#[derive(IntoElement)] + RenderOnce` struct, or the file passes ~500 lines. Don't split before then. |
| GUI core | `apps/gui/src/core/` | Typed UI intent/options helpers used only by the GPUI front end. Must not own DISM, offline registry servicing, Windows Setup orchestration, or first-logon package installs. |
| Agent | `src/runtime/firstlogon/Start-WinMintAgent.ps1` | Runs at first logon; installs editors, WSL distros, and shell layers |
| Setup scripts | `src/runtime/setup/FirstLogon.ps1`, `src/runtime/setup/SetupComplete.ps1` | Machine-phase setup during Windows install |
| Bootstrap | `winmint.ps1` | Downloads release, verifies hash, launches UI |

`src/runtime/image/WinMint.ps1` dot-sources every private module in order — that is the intentional load pattern. Do not call sub-files directly.

## Separation of Concerns

Strict boundaries. Violations here are architectural bugs.

| Layer | Owns | Must not own |
|-------|------|--------------|
| UI | Guided input, previews, validation messages, profile creation, headless engine invocation | DISM calls, WIM servicing, registry hive edits, setup orchestration, live-user package installs |
| Profile | Defaults, derived settings, schema validation, compatibility checks | Mounting images, installing packages |
| Engine | ISO extraction, WIM servicing, drivers, staged setup files, output ISO | GUI controls, user interaction, live-user app installs |
| Setup scripts | Machine-level setup phases during Windows install | User preference prompts, package source policy |
| FirstLogon Agent | Live-user setup, WSL runtime, editors, shell layers, retry state | Offline image servicing, destructive disk choices |
| Reporting | Manifest, logs, user-readable summaries | Business logic decisions |

## JSON Contracts

Three first-class contracts. All business logic passes through these — never bypass them.

| Contract | Generated by | Consumed by | Lives at |
|----------|-------------|-------------|----------|
| `BuildProfile.json` | UI or CLI | Engine, FirstLogon Agent | `output/<build>/` |
| `BuildManifest.json` | Engine | Reports, human audit | `output/<build>/` |
| `BuildDelta.json` | Audit pipeline | GUI review, CLI summaries, reports | `output/<build>/` |
| `state.json` | FirstLogon Agent | Agent retry logic | `%LOCALAPPDATA%\WinMint\state.json` |

**BuildProfile owns:** source ISO path, architecture, device mode (`ThisPC`/`DifferentPC`), edition mode, disk mode/layout, driver source, identity, desktop layers, WSL distros, editors, feature toggles.  
**BuildProfile does not own:** build timestamps, WIM mount paths, download hashes, step success/failure state, UI display strings.

**BuildDelta owns:** generated backend truth for "what WinMint changes" after profile normalization and install-plan derivation. Every record must include phase, contributor source, applicability/suppression metadata, and a concise change list. Do not maintain a separate handwritten authoritative backend behavior summary once a behavior is represented in `BuildDelta`.

Driver sources are conservative by design. `None`, `Host`, and `Custom` remain compatibility values, but Surface driver packs should use either `SurfaceCatalog` or `SurfaceMsiSafe`. `SurfaceCatalog` means `profile.drivers.path` is an exact WinMint Surface catalog device id from `config/surface-drivers.json`; it resolves the official Microsoft Download Center package at build time, downloads it into the temp work directory, verifies Microsoft ownership/signature evidence, then runs the same safe Surface classification path. `SurfaceMsiSafe` is the manual official Surface MSI path. Both paths extract the MSI, require the `SurfaceUpdate` payload, exclude firmware-class drivers from offline injection, and write `WinMint-DriverInventory.json`. The catalog must use Microsoft-owned URLs only; third-party catalogs such as SurfaceTip are research references only and must not be runtime download sources. Do not route Surface recovery-critical installs through raw recursive `Custom` injection unless deliberately investigating an experimental failure.

**Agent step status values:** `pending`, `running`, `ok`, `failed`, `skipped`, `retryable`, `needsReboot`.

Schemas:

- `schemas/winmint.buildprofile.schema.json`
- `schemas/winmint.buildmanifest.schema.json`
- `schemas/winmint.agentstate.schema.json`

Validate with `tests/contract/Test-ProfileInvariants.ps1`.

## Key Files

| File | Purpose |
|------|---------|
| `config/packages.json` | winget / Store / Scoop package catalog |
| `src/runtime/image/Private/Image/Tweaks/` | Registry tweak modules — one `NN-<id>.ps1` per tweak, each carrying its definition (`set`/`remove`/metadata) **and** its `appliesTo` curation predicate. `TweakRegistry.ps1` validates each definition, derives the typed `operations.registry` DOM, and exposes `Get-WinMintSelectedRegistryTweaks`. `Tweaks.ps1` executes the normalized operations through guarded helpers, not loose ad hoc delete/set loops. Add/change a tweak by editing one file there. |
| `config/tweaks.json` | Public metadata mirror of the tweak modules; kept in parity by a contract test (`StaticAssertions.ps1`). Not the executable source. |
| `schemas/winmint.*.schema.json` | JSON Schema for the profile, manifest, and agent-state contracts |
| `config/autounattend.xml` | Windows unattended install template; generated output must ship alongside ISO |
| `assets/runtime/desktop/windhawk/preset.manifest.json` | Windhawk mod preset manifest (installed as a unit, not individual mods) |
| `assets/runtime/desktop/yasb/preset.manifest.json` | YASB preset manifest |
| `assets/runtime/desktop/komorebi/`, `assets/runtime/desktop/yasb/` | Shell layer configs |
| `PSScriptAnalyzerSettings.psd1` | Linter settings |

`output/` and `dist/` are build artifacts — gitignored, do not edit.

## Desktop Shell Model

Layers are **additive and composable**, not mutually exclusive.

| Layer | What it adds |
|-------|-------------|
| Standard Windows | Clean WinMint baseline; no extra shell |
| Windhawk | Shell polish, dock/taskbar styling |
| YASB | Top bar / status surface |
| thide | Taskbar hiding for launcher-centered workflows |
| Komorebi | Tiling window manager |
| Nilesoft Shell | Context-menu polish |

Standard Windows means zero added layers. Windhawk, YASB, thide, Komorebi, and Nilesoft can be freely combined unless a future contract says otherwise. The build/agent must install, configure, and start each selected layer so the desktop matches any UI preview.

## Agent Module Map

| Feature | Module path |
|---------|-------------|
| Package managers | `src/runtime/firstlogon/Modules/PackageManagers.ps1` |
| Editor bootstrap | `src/runtime/firstlogon/Modules/Editors.ps1` |
| Git config | `src/runtime/firstlogon/Modules/Git.ps1` |
| Dotfiles | `src/runtime/firstlogon/Modules/Dotfiles.ps1` |
| WSL2 bootstrap | `src/runtime/firstlogon/Modules/Wsl.ps1` |
| Raycast | `src/runtime/firstlogon/Modules/Raycast.ps1` |
| Launcher key binding | `src/runtime/firstlogon/Modules/LauncherKey.ps1` |
| Shell layers (yasb/thide/komorebi/nilesoft) | `src/runtime/firstlogon/Modules/TilingDesktop.ps1` |
| Windhawk | `src/runtime/firstlogon/Modules/Windhawk.ps1` |
| Profile composition | `src/runtime/firstlogon/Modules/Profiles.ps1` |

Launcher install is opt-in. CLI users choose `-Launcher Raycast` for Raycast or omit the flag for no launcher; selecting `thide` without an explicit launcher defaults the launcher to Raycast. Profile-backed builds set `features.launcher` to `None` or `Raycast`, which becomes `modules.raycast.enabled` in `New-WinMintAgentProfile`. Raycast installs through the Store source, requests only curated no-API-key extensions, and uses Everything as a quiet local filesystem backend: ARM64 targets use the pinned, SHA256-verified upstream `Everything-1.5.0.1415b.ARM64.en-US-Setup.exe`; amd64/x86-64 targets use package-manager `voidtools.Everything.Beta`. Do not add alternate launcher tokens or the ES CLI package unless a runtime requirement proves it is needed. The launcher key module always records the common Copilot hardware-key chord, `Win+Shift+F23`: Store-backed launchers use native Copilot-key app policy when their AUMID is available, and no-launcher builds clear Copilot app key policy so Windows can use the native Search target/fallback. Windows Search and indexing stay on for Start/Settings integrations. Keep optional tray icons hidden unless the icon exposes a real, user-facing status or control surface.

Phone Link policy and live install audit are also opt-in live-user modules. They must stay disabled unless `features.phoneLink` / `features.liveInstallAudit` or the matching CLI flags are explicitly selected. Live install audit is diagnostic and non-blocking: it must write a report and return warning/error counts without failing FirstLogon.

Each module must be idempotent. A failed optional layer must not break the entire first logon. Every step writes `state.json` before and after it runs.

## Package Source Policy

The user does not choose package sources. WinMint decides.

| Source | Used for |
|--------|----------|
| winget | GUI apps, Microsoft apps, signed installers, shell integrations, desktop services, and packages where the upstream installer is canonical |
| Scoop | User-local developer CLI tools and toolchain plumbing. Scoop is installed during FirstLogon with the official installer; MinGit is the baseline Windows-host Git provider; Starship is the baseline Windows-host prompt with the `nerd-font-symbols` preset; selected Neovim is Scoop-owned. |
| GitHub release | Reserved for future upstream-asset-backed tools when winget metadata lags or a specific release asset/architecture is needed |
| Store source | Store-backed packages where the upstream app is distributed through Microsoft Store and winget surfaces them via `msstore` |
| Direct download | Narrow pinned exception only: the SHA256-verified native Everything 1.5 ARM64 installer used as Raycast's ARM64 file-search backend |

For an ARM64/aarch64 source ISO, FirstLogon must aggressively prefer native ARM64 package assets in both winget and Scoop where the package-manager metadata supports them. For an amd64/x64 ISO, do not force architecture flags; use the package manager's default selection.

## Debloat Tiers

**Tier 0 — Never touch:** Windows Update, Defender, SmartScreen, Firewall, Store infrastructure, Desktop App Installer, winget, WebView2/Edge runtime, WSL, Virtual Machine Platform, Hyper-V networking, IPv6, WinRE, WinSxS component store, UAC.

**Tier 1 — Apply by default (WinMint Core):** DMA-aware Microsoft AppX removal (Clipchamp, Xbox unless `-KeepGaming`, Solitaire, Teams consumer, Recall, Copilot unless `-KeepCopilot`, Dev Home, WebExperience, Calculator, Quick Assist, Sound Recorder, Sticky Notes, Maps, To Do, OneNote, Remote Desktop Store client, legacy media apps, etc.), advertising/content surfaces, Edge noise debloat (first-run/startup boost/promos/inline compose/web AI APIs while preserving explicit Edge Copilot page-context chat), Edge browser removal through the normal DMA app uninstaller unless `-KeepEdge` is selected, OneDrive removal, GameDVR plus no-op Game Bar protocol handlers when Xbox/Game Bar is removed, Home-safe privacy policy, Storage Sense safe mode, Modern Standby network-off, Delivery Optimization peer-to-peer off with Windows Update preserved, vendor driver co-installers blocked with Windows Update driver delivery preserved, WPBT disable, and Explorer dev-QoL defaults (show extensions, hidden files, keep Home, hide Gallery, long paths, End Task on the taskbar, quiet taskbar/tray affordances, local clipboard history on, cloud clipboard upload off). Small reinstallable inbox apps are not protected platform components; users can reinstall them from Store/App Installer after setup. Default also applies a narrower serviceable AI policy: Recall is always removed; imposed Copilot app/shell surfaces, Notepad AI, web AI APIs, and app access to system/generative AI models are disabled unless `-KeepCopilot` is selected. Click to Do, Paint AI, Edge Copilot page-context chat, the local Settings agent, Office AI, agent connectors, and workspaces are not touched by the default AI policy. WebView2 / Edge runtime infrastructure is never removed. The developer QoL tweaks (Developer Mode, PS RemoteSigned, .NET/PS telemetry opt-out, elevated terminal, OpenSSH, Scoop, MinGit, Starship with `nerd-font-symbols`) are baseline. Windows Terminal defaults to PowerShell 7, Cascadia Code NF, One Half Dark, no audible bell, and centered launch. Archive/extraction stays native; do not install a third-party archive manager by default. After successful FirstLogon cleanup, create a final `WinMint post-install complete` System Restore point.

Broad third-party and OEM AppX prefixes should stay candidate-only by default. DMA setup reduces the expected default-app/promotional payload, so do not expand normal removal into a broad OEM cleanup list unless a specific source ISO proves it is needed and the catalog/test contract is updated deliberately.

**Tier 3 — Reject:** Disabling Defender/Firewall/SmartScreen, disabling Windows Update or WaaSMedic, removing WinSxS, removing WebView2, disabling IPv6, disabling Hyper-V/HNS networking services, hosts-file endpoint blocks, blanket scheduled task disabling, CPU security mitigation disables, "Ultimate Performance" mode by default.

See `docs/Windows-Debloat-Strategy.md` for the full audit and Tier 2 candidates.

## Architecture Invariants

The backend architecture refactor is complete and merged. These four properties
are now established invariants — preserve them, do not regress them:

1. UI saves a complete `BuildProfile.json` before starting
2. Engine builds from a profile without GUI code loaded
3. Manifest explains the build without scraping logs
4. FirstLogon resumes after interruption via `%LOCALAPPDATA%\WinMint\state.json`

`docs/Project-Structure.md` is the repository layout contract. Keep the app
runnable after every change; do not rewrite working subsystems wholesale.

## PSScriptAnalyzer

Run: `Invoke-ScriptAnalyzer -Path . -Settings PSScriptAnalyzerSettings.psd1`

Intentional exclusions — do not "fix" these:

| Rule | Why it is excluded |
|------|--------------------|
| `PSUseShouldProcessForStateChangingFunctions` | UI/build helpers don't need -WhatIf |
| `PSReviewUnusedParameter` | DryRun param used indirectly via CmdletBinding |
| `PSAvoidUsingInvokeExpression` | Dot-sourcing internal blocks is the load pattern |
| `PSAvoidUsingWriteHost` | Script entry points and validation helpers intentionally report directly to the console |

## Architecture Detection

Parsed from ISO filename via case-insensitive regex. Cross-checked against WIM metadata and `setup.exe` PE header — all three must agree or the build aborts with no side effects. If the filename has no arch marker, the script prompts once at runtime.

## Distribution

Short launch path: `irm https://winmint.yanai.sh | iex`
Default bootstrap behavior is ephemeral: download the release zip and `.sha256`
to a unique `%TEMP%` session, verify SHA256, extract and run from that session,
wait for the launched process, then best-effort remove the session. Do not
reintroduce a default `%LOCALAPPDATA%\WinMint\versions` install/cache path.
Durable release cache behavior is explicit opt-in only through launcher switches
such as `-InstallRoot` or `-CacheRelease`.
Bootstrap failures must go through the friendly failure envelope in `winmint.ps1`
with operation, failure kind, reason, recovery guidance, and retry-safety text.
Preserve the explicit failure kinds: network, integrity, package, runtime,
elevation, relaunch, usage, and unexpected.
Cloudflare Worker source: `cloudflare/winmint/` — deploy with `bunx wrangler@latest deploy --config wrangler.jsonc`

Release bundle: `tools/release/New-WinMintReleaseBundle.ps1` → produces `dist/WinMint-<version>.zip` + `.sha256`. Upload both to the matching GitHub release.
CI/CD policy: normal pushes and PRs validate only. Releases are tag/manual driven through `.github/workflows/release.yml`; push a `v*` tag or run the workflow manually to build and upload the zip plus hash assets. Do not publish on every push.

## Documentation Ownership

- Update `README.md` when user-facing behavior, setup commands, requirements, or rationale changes.
- Update `AGENTS.md` when architecture boundaries, coding constraints, repo contracts, or agent workflow rules change.
- Treat `docs/codebase/` as current-development snapshots for onboarding and audits, not as a continuous authoritative source of truth.
- Update schemas and contract tests together whenever `BuildProfile.json`, `BuildManifest.json`, or `state.json` shape changes.

## Commit Style

Conventional commits: `feat(scope):`, `fix(scope):`, `refactor:`, `docs:`, etc.  
Scope = component name: `windhawk`, `agent`, `shell`, `firstlogon`, `engine`, `profile`, `ui`, `komorebi`, `yasb`.
