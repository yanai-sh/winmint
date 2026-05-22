# WinMint — Agent context

Windows 11 ISO builder. PowerShell-only, Windows-native. Requires PS 7.3+.
Development usually happens from WSL or an editor, but all project scripts execute on Windows.

`AGENTS.md` is the compact implementation contract for coding agents. User-facing product behavior, usage examples, and rationale belong in `README.md`.

The core design rule: **UI creates intent. Engine performs work. Reports explain work. FirstLogon finishes live-user setup.**

## Product stance (opinionated)

- **User ISO is the truth.** There is no pinned “golden” Windows build inside the repo. Whatever **source ISO** the user picks (subject to documented minimums, e.g. Windows 11 **25H2+** in `README.md`) is the version DISM services. AppX prefixes and registry stamps are **best-effort** against common SKUs; odd OEM bundles may need follow-up outside the wizard.
- **Source choice stays simple.** The user-provided ISO is the source of truth. If the user already ran UUP Dump and has a final ISO, they must provide that ISO directly with `-SourceIso`. `-UupDumpSource` accepts a UUP Dump conversion zip only when the user wants WinMint to prepare or validate the ISO; WinMint must not expose UUP converter knobs as public product choices and must not accept converted UUP folders as a second source contract. If a UUP Dump zip is provided, WinMint prepares/uses the ISO with one opinionated policy: include updates, run component cleanup, prefer serviceable WIM output, validate the final ISO, and journal source-prep phases. Do not bundle Microsoft payloads or silently download them; require only a high-level consent/automation acknowledgement when network download or conversion is needed.
- **No debloat/performance wizard flags.** Defaults live in engine/profile/setup scripts only—one coherent WinMint posture, not a choice matrix.
- **Optional profile groups, not granular toggles.** The baseline is `Minimal`; additive groups are `Developer`, `CopilotPlus`, `Gaming`, and `DesktopUI`. Multiple groups may be selected together. CLI spellings are `-Developer`, `-Copilot`, `-Gaming`, and `-DesktopUI`/`--Desktop-UI`. UI pages must appear only when their group needs configuration: developer options for `Developer`, shell customization for `DesktopUI`.
- **No maintenance payload.** WinMint must not leave a maintenance scheduled task, background service, or maintenance script behind on the installed system. Post-update drift is the user’s responsibility after installation; maintenance experiments do not belong under shipped runtime/setup folders.
- **Destructive disk behavior is explicit.** Disk modes are `Manual`, `AutoWipeDisk0`, and `DualBootReserved`. Dual-boot mode reserves Windows space using one of `WindowsHeavy`, `Balanced`, `EvenSplit`, or `LinuxHeavy`, and leaves the rest unallocated for another OS.

## Commands

```powershell
# Validate syntax + PSScriptAnalyzer (run from project root on Windows)
pwsh -NoProfile -File tools\validation\Validate.ps1

# Smoke-test profile invariants (no ISO or Windows required)
pwsh -NoProfile -File tests\contract\Test-ProfileInvariants.ps1

# Console build (dry run — no ISO required)
pwsh -NoProfile -File WinMint-CLI.ps1 -DryRun

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

| Layer | Entry point | Purpose |
|-------|-------------|---------|
| CLI | `WinMint-CLI.ps1` | Headless/console entry; delegates directly to engine |
| Engine | `src/engine/WinMint.ps1` | Dot-sources all private modules; owns DISM/WIM servicing |
| UI | `WinMint-GUI.ps1`; `apps/gui/` | GPUI is the only shipped GUI. The GPUI app uses `gpui-animation` for state-driven hover transitions; interactive wrappers must use `AnimatedWrapper::on_click` (not the inner `div`’s `on_click`) so the animation hook is not overwritten. |
| Rust core | `crates/winmint-core/`, `crates/winmintctl/` | Typed contract helpers and small validation/normalization tools. Must not own DISM, offline registry servicing, Windows Setup orchestration, or first-logon package installs. |
| Agent | `src/agent/Start-WinMintAgent.ps1` | Runs at first logon; installs editors/WSL/shell layers |
| Setup scripts | `src/setup/FirstLogon.ps1`, `src/setup/SetupComplete.ps1` | Machine-phase setup during Windows install |
| Bootstrap | `winmint.ps1` | Downloads release, verifies hash, launches UI |

`src/engine/WinMint.ps1` dot-sources every private module in order — that is the intentional load pattern. Do not call sub-files directly.

## Separation of Concerns

Strict boundaries. Violations here are architectural bugs.

| Layer | Owns | Must not own |
|-------|------|--------------|
| UI | Guided input, previews, validation messages, profile creation | DISM calls, WIM servicing, registry hive edits |
| Profile | Defaults, derived settings, schema validation, compatibility checks | Mounting images, installing packages |
| Engine | ISO extraction, WIM servicing, drivers, staged setup files, output ISO | GUI controls, user interaction, live-user app installs |
| Setup scripts | Machine-level setup phases during Windows install | User preference prompts, package source policy |
| FirstLogon Agent | Live-user setup, WSL, editors, shell layers, retry state | Offline image servicing, destructive disk choices |
| Reporting | Manifest, logs, user-readable summaries | Business logic decisions |

## JSON Contracts

Three first-class contracts. All business logic passes through these — never bypass them.

| Contract | Generated by | Consumed by | Lives at |
|----------|-------------|-------------|----------|
| `BuildProfile.json` | UI or CLI | Engine, FirstLogon Agent | `output/<build>/` |
| `BuildManifest.json` | Engine | Reports, human audit | `output/<build>/` |
| `state.json` | FirstLogon Agent | Agent retry logic | `%LOCALAPPDATA%\WinMint\state.json` |

**BuildProfile owns:** source ISO path, architecture, device mode (`ThisPC`/`DifferentPC`), edition mode, disk mode/layout, driver source, identity, desktop layers, WSL distros, editors, feature toggles.  
**BuildProfile does not own:** build timestamps, WIM mount paths, download hashes, step success/failure state, UI display strings.

**Agent step status values:** `pending`, `running`, `ok`, `failed`, `skipped`, `retryable`, `needsReboot`.

Schemas:

- `schemas/winmint.buildprofile.schema.json`
- `schemas/winmint.buildmanifest.schema.json`
- `schemas/winmint.agentstate.schema.json`

Validate with `tests/contract/Test-ProfileInvariants.ps1`.

## Key Files

| File | Purpose |
|------|---------|
| `config/profiles.json` | Named build profiles |
| `config/packages.json` | winget package catalog |
| `config/tweaks.json` | Registry tweak definitions |
| `schemas/winmint.*.schema.json` | JSON Schema for the profile, manifest, and agent-state contracts |
| `config/autounattend.xml` | Windows unattended install template; generated output must ship alongside ISO |
| `assets/runtime/desktop/windhawk/preset.json` | Windhawk mod preset (installed as a unit, not individual mods) |
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
| Komorebi | Tiling window manager |

Standard Windows means zero added layers. Windhawk, YASB, and Komorebi can be freely combined. The build/agent must install, configure, and start each selected layer so the desktop matches any UI preview.

## Agent Module Map

| Feature | Module path |
|---------|-------------|
| Package managers | `src/agent/Modules/PackageManagers.ps1` |
| Editor bootstrap | `src/agent/Modules/Editors.ps1` |
| Git config | `src/agent/Modules/Git.ps1` |
| Dotfiles | `src/agent/Modules/Dotfiles.ps1` |
| WSL2 bootstrap | `src/agent/Modules/Wsl.ps1` |
| Flow Launcher + Everything | `src/agent/Modules/FlowEverything.ps1` |
| Raycast | `src/agent/Modules/Raycast.ps1` |
| Tiling desktop (komorebi/yasb) | `src/agent/Modules/TilingDesktop.ps1` |
| Windhawk | `src/agent/Modules/Windhawk.ps1` |
| Profile composition | `src/agent/Modules/Profiles.ps1` |

Launcher install is opt-in and mutually exclusive. CLI users choose `-Launcher FlowEverything` for Flow Launcher plus Everything Alpha, `-Launcher Raycast` for Raycast, or omit the flag for no launcher. Profile-backed builds set `features.launcher` to `None`, `FlowEverything`, or `Raycast`, which becomes `modules.flowEverything.enabled` or `modules.raycast.enabled` in `New-WinMintAgentProfile`. Windows Search and indexing stay on for Start/Settings integrations. Minimize tray icon bloat: Everything runs as a background service/index provider for Flow and must hide its tray icon by default; keep other optional tray icons hidden unless the icon exposes a real, user-facing status or control surface.

Phone Link policy and live install audit are also opt-in live-user modules. They must stay disabled unless `features.phoneLink` / `features.liveInstallAudit` or the matching CLI flags are explicitly selected.

Each module must be idempotent. A failed optional layer must not break the entire first logon. Every step writes `state.json` before and after it runs.

## Package Source Policy

The user does not choose package sources. WinMint decides.

| Source | Used for |
|--------|----------|
| winget | GUI apps, Microsoft apps, signed installers, CLI tools, and packages where the upstream installer is canonical |
| GitHub release | Tools where winget metadata lags or a specific release asset/architecture is needed |
| Store source | Store-only packages or packages needing Store identity for Windows integration |

## Debloat Tiers

**Tier 0 — Never touch:** Windows Update, Defender, SmartScreen, Firewall, Store infrastructure, Desktop App Installer, winget, WebView2/Edge runtime, WSL, Virtual Machine Platform, Hyper-V networking, IPv6, WinRE, WinSxS component store, UAC.

**Tier 1 — Apply by default (WinMint Core):** Consumer AppX removal (Clipchamp, Xbox, Solitaire, Teams consumer, Recall, Copilot, Dev Home, etc.), advertising/content surfaces, Edge noise (first-run/startup boost/promos), OneDrive autostart, GameDVR, Explorer dev-QoL defaults (show extensions, hidden files, long paths).

**Tier 3 — Reject:** Disabling Defender/Firewall/SmartScreen, disabling Windows Update or WaaSMedic, removing WinSxS, removing WebView2, disabling IPv6, disabling Hyper-V/HNS networking services, hosts-file endpoint blocks, blanket scheduled task disabling, CPU security mitigation disables, "Ultimate Performance" mode by default.

See `docs/Windows-Debloat-Strategy.md` for the full audit and Tier 2 candidates.

## Architecture Phase (current branch)

Branch `architecture/profile-engine` is converging toward:

1. UI saves a complete `BuildProfile.json` before starting
2. Engine builds from a profile without GUI code loaded
3. Manifest explains the build without scraping logs
4. FirstLogon resumes after interruption via `%LOCALAPPDATA%\WinMint\state.json`

Migration is incremental — the app must stay runnable after every step. Do not rewrite; use `docs/Project-Structure.md` as the repository layout contract.

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
Cloudflare Worker source: `cloudflare/winmint/` — deploy with `bunx wrangler@latest deploy --config wrangler.jsonc`

Release bundle: `tools/release/New-WinMintReleaseBundle.ps1` → produces `dist/WinMint-<version>.zip` + `.sha256`. Upload both to the matching GitHub release.
CI/CD policy: normal pushes and PRs validate only. Releases are tag/manual driven through `.github/workflows/release.yml`; push a `v*` tag or run the workflow manually to build and upload the zip plus hash assets. Do not publish on every push.

## Documentation Ownership

- Update `README.md` when user-facing behavior, setup commands, requirements, or rationale changes.
- Update `AGENTS.md` when architecture boundaries, coding constraints, repo contracts, or agent workflow rules change.
- Update schemas and contract tests together whenever `BuildProfile.json`, `BuildManifest.json`, or `state.json` shape changes.

## Commit Style

Conventional commits: `feat(scope):`, `fix(scope):`, `refactor:`, `docs:`, etc.  
Scope = component name: `windhawk`, `agent`, `shell`, `firstlogon`, `engine`, `profile`, `ui`, `komorebi`, `yasb`.
