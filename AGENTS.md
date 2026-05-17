# WinMint — Agent context

Windows 11 ISO builder. PowerShell-only, Windows-native. Requires PS 7.3+.
Development happens in WSL; all scripts execute on Windows.

The core design rule: **UI creates intent. Engine performs work. Reports explain work. FirstLogon finishes live-user setup.**

## Product stance (opinionated)

- **User ISO is the truth.** There is no pinned “golden” Windows build inside the repo. Whatever **source ISO** the user picks (subject to documented minimums, e.g. Windows 11 **25H2+** in `README.md`) is the version DISM services. AppX prefixes and registry stamps are **best-effort** against common SKUs; odd OEM bundles may need follow-up outside the wizard.
- **Source choice stays simple.** WinWS may accept either an existing ISO or a user-provided UUP Dump package/folder, but it must not expose UUP converter knobs as public product choices. If a UUP Dump source is provided, WinWS detects whether it is a zip, untouched recipe folder, downloaded-but-not-converted folder, already converted folder, or final ISO; then it prepares/uses the ISO with one opinionated policy: include updates, run component cleanup, prefer serviceable WIM output, validate the final ISO, and journal source-prep phases. Do not bundle Microsoft payloads or silently download them; require only a high-level consent/automation acknowledgement when network download or conversion is needed.
- **No debloat/performance wizard flags.** Defaults live in engine/profile/setup scripts only—one coherent WinWS posture, not a choice matrix.
- **Optional profile groups, not granular toggles.** The baseline is `Minimal`; additive groups are `Developer`, `CopilotPlus`, `Gaming`, and `DesktopUI`. Multiple groups may be selected together. CLI spellings are `-Developer`, `-Copilot`, `-Gaming`, and `-DesktopUI`/`--Desktop-UI`. UI pages must appear only when their group needs configuration: developer options for `Developer`, shell customization for `DesktopUI`.
- **Maintain is frozen off.** `SetupComplete.ps1` leaves `$RegisterWinWSMaintainScheduledTask = $false`; `Maintain.ps1` stays on disk for **manual runs or forks**, not a shipped boot task. Post-update drift is the user’s unless they opt back in locally.

## Commands

```powershell
# Validate syntax + PSScriptAnalyzer (run from project root on Windows)
pwsh -NoProfile -File scripts\Validation\Validate.ps1

# Smoke-test profile invariants (no ISO or Windows required)
pwsh -NoProfile -File scripts\test\Test-ProfileInvariants.ps1

# Console build (dry run — no ISO required)
pwsh -NoProfile -File WinMint-CLI.ps1 -DryRun

# UI build
pwsh -NoProfile -File WinMint-UI.ps1

# UI build with auto-audit — wizard launches and a sibling shell drives it
# through every page with input/*.iso + input/*.msi fixtures. Primary artifacts
# are semantic JSON under output\ui-snapshots\ (UIA tree + probe); PNGs optional.
pwsh -NoProfile -File WinMint-UI.ps1 -Audit

# Fast UI fixture capture for design iteration. Uses -FixtureMode; writes
# output\ui-audit\<run>\*.ui.json (+ audit.json). Optional PNG only if you pass
# -IncludePng through Drive-Ui from a custom driver.
pwsh -NoProfile -File scripts\ui-automation\Capture-UiFixtureStates.ps1

# Release bundle (outputs to dist\)
pwsh -NoProfile -File scripts\release\New-WinMintReleaseBundle.ps1 -Version v0.2.0

# Optional PNG capture (pixel/visual review). Prefer Drive-Ui Snapshot for JSON.
pwsh -NoProfile -File scripts\ui-automation\Capture-UiScreenshot.ps1 -Page 1

# Drive the running WinWS UI programmatically (UIA). Snapshot writes semantic JSON
# to output\ui-snapshots\; use -IncludePng for a bitmap. All control IDs are WPF
# x:Name values. Outputs JSON; non-zero exit on error. Run from an admin shell
# since WinWS auto-elevates.
pwsh -NoProfile -File scripts\ui-automation\Drive-Ui.ps1 -Action Click -Name BtnNext
pwsh -NoProfile -File scripts\ui-automation\Drive-Ui.ps1 -Action SetText -Name TxtComputerNameSplash -Value 'test-pc'
pwsh -NoProfile -File scripts\ui-automation\Drive-Ui.ps1 -Action SetIso        # auto-finds input\*.iso
pwsh -NoProfile -File scripts\ui-automation\Drive-Ui.ps1 -Action SetDriver     # auto-finds input\*.msi
pwsh -NoProfile -File scripts\ui-automation\Drive-Ui.ps1 -Action GetCurrentPage
pwsh -NoProfile -File scripts\ui-automation\Drive-Ui.ps1 -Action GoToPage -Page 3
pwsh -NoProfile -File scripts\ui-automation\Drive-Ui.ps1 -Action Snapshot -Label page3-desktop
pwsh -NoProfile -File scripts\ui-automation\Drive-Ui.ps1 -Action Snapshot -Label visual -IncludePng
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
| Engine | `src/WinWS/WinWS.ps1` | Dot-sources all private modules; owns DISM/WIM servicing |
| UI | `WinMint-UI.ps1` → `src/WinWS.UI/` | WPF wizard; produces `BuildProfile.json`; no build logic |
| Agent | `src/WinWS.Agent/Start-WinWSAgent.ps1` | Runs at first logon; installs editors/WSL/shell layers |
| Setup scripts | `scripts/setup/FirstLogon.ps1`, `scripts/setup/SetupComplete.ps1` | Machine-phase setup during Windows install |
| Bootstrap | `winmint.ps1` | Downloads release, verifies hash, launches UI |

`src/WinWS/WinWS.ps1` dot-sources every private module in order — that is the intentional load pattern. Do not call sub-files directly.

## Separation of Concerns

Strict boundaries. Violations here are architectural bugs.

| Layer | Owns | Must not own |
|-------|------|--------------|
| UI | Guided input, previews, validation messages, profile creation | DISM calls, WIM servicing, registry hive edits |
| Profile | Defaults, derived settings, schema validation, compatibility checks | Mounting images, installing packages |
| Engine | ISO extraction, WIM servicing, drivers, staged setup files, output ISO | WPF controls, user interaction, live-user app installs |
| Setup scripts | Machine-level setup phases during Windows install | User preference prompts, package source policy |
| FirstLogon Agent | Live-user setup, WSL, editors, shell layers, retry state | Offline image servicing, destructive disk choices |
| Reporting | Manifest, logs, user-readable summaries | Business logic decisions |

## JSON Contracts

Three first-class contracts. All business logic passes through these — never bypass them.

| Contract | Generated by | Consumed by | Lives at |
|----------|-------------|-------------|----------|
| `BuildProfile.json` | UI or CLI | Engine, FirstLogon Agent | `output/<build>/` |
| `BuildManifest.json` | Engine | Reports, human audit | `output/<build>/` |
| `state.json` | FirstLogon Agent | Agent retry logic | `%LOCALAPPDATA%\WinWS\state.json` |

**BuildProfile owns:** source ISO path, architecture, device mode (`ThisPC`/`DifferentPC`), edition mode, driver source, identity, desktop layers, WSL distros, editors, feature toggles.  
**BuildProfile does not own:** build timestamps, WIM mount paths, download hashes, step success/failure state, UI display strings.

**Agent step status values:** `pending`, `running`, `ok`, `failed`, `skipped`, `retryable`, `needsReboot`.

Schemas live in `schemas/`. Validate with `scripts/test/Test-ProfileInvariants.ps1`.

## Key Files

| File | Purpose |
|------|---------|
| `config/profiles.json` | Named build profiles |
| `config/packages.json` | winget package catalog |
| `config/tweaks.json` | Registry tweak definitions |
| `schemas/*.json` | JSON Schema for all three contracts |
| `autounattend.xml` | Windows unattended install — must ship alongside ISO |
| `assets/windhawk/preset.json` | Windhawk mod preset (installed as a unit, not individual mods) |
| `assets/komorebi/`, `assets/yasb/` | Shell layer configs |
| `PSScriptAnalyzerSettings.psd1` | Linter settings |

`output/` and `dist/` are build artifacts — gitignored, do not edit.

## Desktop Shell Model

Layers are **additive and composable**, not mutually exclusive.

| Layer | What it adds |
|-------|-------------|
| Standard Windows | Clean WinWS baseline; no extra shell |
| Windhawk | Shell polish, dock/taskbar styling |
| YASB | Top bar / status surface |
| Komorebi | Tiling window manager |

Standard Windows means zero added layers. Windhawk, YASB, and Komorebi can be freely combined. The build/agent must install, configure, and start each selected layer so the desktop matches any UI preview.

## Agent Module Map

| Feature | Module path |
|---------|-------------|
| Package managers | `src/WinWS.Agent/Modules/PackageManagers.ps1` |
| Editor bootstrap | `src/WinWS.Agent/Modules/Editors.ps1` |
| Git config | `src/WinWS.Agent/Modules/Git.ps1` |
| Dotfiles | `src/WinWS.Agent/Modules/Dotfiles.ps1` |
| WSL2 bootstrap | `src/WinWS.Agent/Modules/Wsl.ps1` |
| Flow Launcher + Everything | `src/WinWS.Agent/Modules/FlowEverything.ps1` |
| Tiling desktop (komorebi/yasb) | `src/WinWS.Agent/Modules/TilingDesktop.ps1` |
| Windhawk | `src/WinWS.Agent/Modules/Windhawk.ps1` |
| Profile composition | `src/WinWS.Agent/Modules/Profiles.ps1` |

Flow Launcher and Everything Alpha install on first logon when either `Developer` or `DesktopUI` is selected (`modules.flowEverything.enabled` is derived from profile groups in `New-WinWSAgentProfile`). If both groups are selected, the shared module still runs once. Windows Search and indexing stay on for Start/Settings integrations. Minimize tray icon bloat: Everything runs as a background service/index provider for Flow and must hide its tray icon by default; keep other optional tray icons hidden unless the icon exposes a real, user-facing status or control surface.

Each module must be idempotent. A failed optional layer must not break the entire first logon. Every step writes `state.json` before and after it runs.

## Package Source Policy

The user does not choose package sources. WinWS decides.

| Source | Used for |
|--------|----------|
| winget | GUI apps, Microsoft apps, signed installers, CLI tools, and packages where the upstream installer is canonical |
| GitHub release | Tools where winget metadata lags or a specific release asset/architecture is needed |
| Store source | Store-only packages or packages needing Store identity for Windows integration |

## Debloat Tiers

**Tier 0 — Never touch:** Windows Update, Defender, SmartScreen, Firewall, Store infrastructure, Desktop App Installer, winget, WebView2/Edge runtime, WSL, Virtual Machine Platform, Hyper-V networking, IPv6, WinRE, WinSxS component store, UAC.

**Tier 1 — Apply by default (WinWS Core):** Consumer AppX removal (Clipchamp, Xbox, Solitaire, Teams consumer, Recall, Copilot, Dev Home, etc.), advertising/content surfaces, Edge noise (first-run/startup boost/promos), OneDrive autostart, GameDVR, Explorer dev-QoL defaults (show extensions, hidden files, long paths).

**Tier 3 — Reject:** Disabling Defender/Firewall/SmartScreen, disabling Windows Update or WaaSMedic, removing WinSxS, removing WebView2, disabling IPv6, disabling Hyper-V/HNS networking services, hosts-file endpoint blocks, blanket scheduled task disabling, CPU security mitigation disables, "Ultimate Performance" mode by default.

See `docs/Windows-Debloat-Strategy.md` for the full audit and Tier 2 candidates.

## Architecture Phase (current branch)

Branch `architecture/profile-engine` is converging toward:

1. UI saves a complete `BuildProfile.json` before starting
2. Engine builds from a profile without WPF loaded
3. Manifest explains the build without scraping logs
4. FirstLogon resumes after interruption via `%LOCALAPPDATA%\WinWS\state.json`

Migration is incremental — the app must stay runnable after every step. Do not rewrite; refactor toward the target layout in `docs/Architecture-Plan.md`.

## PSScriptAnalyzer

Run: `Invoke-ScriptAnalyzer -Path . -Settings PSScriptAnalyzerSettings.psd1`

Intentional exclusions — do not "fix" these:

| Rule | Why it is excluded |
|------|--------------------|
| `PSUseShouldProcessForStateChangingFunctions` | UI/build helpers don't need -WhatIf |
| `PSReviewUnusedParameter` | DryRun param used indirectly via CmdletBinding |
| `PSAvoidUsingInvokeExpression` | Dot-sourcing internal blocks is the load pattern |
| `PSAvoidUsingWriteHost` | WPF `.Add()` returns int; `Out-Null` suppresses it correctly |

## Architecture Detection

Parsed from ISO filename via case-insensitive regex. Cross-checked against WIM metadata and `setup.exe` PE header — all three must agree or the build aborts with no side effects. If the filename has no arch marker, the script prompts once at runtime.

## Distribution

Short launch path: `irm https://winmint.yanai.sh | iex`  
Cloudflare Worker source: `cloudflare/winmint/` — deploy with `bunx wrangler@latest deploy --config wrangler.jsonc`

Release bundle: `scripts/release/New-WinMintReleaseBundle.ps1` → produces `dist/WinMint-<version>.zip` + `.sha256`. Upload both to the matching GitHub release.

## Commit Style

Conventional commits: `feat(scope):`, `fix(scope):`, `refactor:`, `docs:`, etc.  
Scope = component name: `windhawk`, `agent`, `shell`, `firstlogon`, `engine`, `profile`, `ui`, `komorebi`, `yasb`.
