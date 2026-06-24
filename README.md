<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/brand/readme/winmint_hero_dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="assets/brand/readme/winmint_hero_light.svg">
  <img src="assets/brand/readme/winmint_hero_light.svg" alt="WinMint" width="540">
</picture>

Windows 11 ISO builder for clean developer workstation installs.

[![License](https://img.shields.io/badge/License-GPL--2.0--or--later-3ABf7c?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%2011%2025H2%2B-0078D6?style=flat-square&logo=windows11&logoColor=white)](#requirements)
[![PowerShell](https://img.shields.io/badge/PowerShell-7.6.2%2B-5391FE?style=flat-square&logo=powershell&logoColor=white)](#requirements)
[![UI](https://img.shields.io/badge/UI-GPUI%20%2F%20Rust-DEA584?style=flat-square&logo=rust&logoColor=white)](apps/gui)

</div>

---

WinMint starts from the Windows ISO you provide, applies a workstation baseline,
stages setup and first-logon automation, and emits a bootable ISO. It does not
ship a hidden golden Windows image; your source ISO is the serviced source.

## Quick start

```powershell
# GUI
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-GUI.ps1

# Author a profile, then dry-run a build from it (requires elevated PowerShell, or add -AllowElevate)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 new .\BuildProfile.json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 build .\BuildProfile.json -DryRun
```

```powershell
# Remote launcher (downloads, verifies, launches, then cleans up the release)
irm https://winmint.yanai.sh | iex
```

| Entry point | Purpose |
|-------------|---------|
| `WinMint-GUI.ps1` | GPUI launcher |
| `WinMint-CLI.ps1` | Headless and profile-driven builds |
| `winmint.ps1` | Download, SHA256-verify, temp-extract, launch, and clean up the latest release |

The remote launcher is intentionally ephemeral. A normal `irm | iex` launch does
not install WinMint into `%LOCALAPPDATA%` or leave a release cache behind; the
intended durable output is the ISO and artifacts you explicitly choose.

## What it builds

WinMint uses a subtractive default plus a small set of opt-in keep flags, not a
debloat dashboard. The default build removes everything and folds the developer
quality-of-life tweaks (Developer Mode, PowerShell RemoteSigned, .NET and
PowerShell telemetry opt-out, elevated-terminal menu, OpenSSH, WSL2/VMP, and
the default system fonts/cursors) into the baseline. PowerShell 7 is staged by
default, Windows Terminal opens it as the default profile with `-NoLogo`, uses
Cascadia Code NF with the One Half Dark color scheme, disables the audible bell,
and centers on launch. FirstLogon installs Scoop using the official installer
and installs MinGit plus Starship through Scoop as Windows-host developer shell
plumbing. Starship is configured with the `nerd-font-symbols` preset by default.
XDG-aware tools get Linux-like defaults: config, data,
state, and cache live under dotfolders in the user profile, and runtime data
uses a temp-backed per-user directory. WinMint also creates `~/bin` and
`~/.local/bin`, adds both to the user `PATH`, keeps clipboard history local-on,
and leaves cloud clipboard upload off unless Phone Link is explicitly selected.
Cloud-backed consumer suggestions, Spotlight tips, Share Sheet promotions, and
welcome/recommendation surfaces are disabled through documented policy where the
source Windows SKU honors those policies. FirstLogon also mirrors those quiet
defaults into the live user profile: backup/setup pressure prompts stay off,
the lock screen uses the local WinMint image instead of Spotlight rotation, and
nonessential taskbar/tray affordances start hidden. Windows Update remains
enabled, but Delivery Optimization peer upload/download behavior is disabled so
the PC is not used to serve updates to other devices. Windows Update driver
delivery stays enabled, but vendor driver co-installers are blocked so hardware
drivers do not silently bring companion apps and tray utilities with them.
Archive handling stays native; WinMint does not install a third-party archive manager by default. After
FirstLogon succeeds, WinMint removes its setup residue and creates a final
`WinMint post-install complete` System Restore point.
WinMint is WSL-first by design: the platform plumbing is always enabled, while
individual Linux distros remain optional installs. Dev Drive is not a WinMint
default; users set that up separately if they want it.

Build output includes `WinMint-Toolchain.winget`, a reviewable WinGet
Configuration handoff for selected winget/msstore Windows-side tools. Scoop-owned
developer CLIs are intentionally excluded from that file. WinMint does not
auto-run the handoff during setup.

Configuration is set when you author a profile — `WinMint-CLI.ps1 new <out> ...`
or the GUI. The opt-in flags below are `new` flags; `build <profile>` then
consumes the profile.

| Domain | Default | Opt-in flag (on `new`) |
|--------|---------|-------------|
| AI / Copilot / Recall | Recall removed; imposed Copilot app/shell, Notepad AI, web AI APIs, and app AI-model access disabled | `-KeepCopilot` keeps non-Recall Copilot+ AI policy/app surfaces; Recall stays removed |
| Edge browser | Removal requested; debloat policies always applied | `-KeepEdge` keeps the browser installed and debloated |
| Xbox / Game Bar | Removed; Game Bar protocol prompts are no-op'd | `-KeepGaming` keeps gaming apps and performance tweaks |
| File Explorer | Shows extensions/hidden files, keeps Home, hides Gallery | baseline |
| Shell layers | Off | `-DesktopUI`, or `-Install windhawk,yasb,thide,komorebi,nilesoft` |
| Launcher | Off, except `thide` defaults to Raycast | `-Launcher Raycast` |
| Browsers | None installed by default | `-Browser zen-browser,helium,firefox-developer-edition,brave,edge` |
| Power plan | Balanced | `-PowerPlan EnergySaver`, `HighPerformance`, or `UltimatePerformance`; other schemes are preserved |
| Dev tweaks, OpenSSH, WSL2, Scoop, MinGit, Starship with `nerd-font-symbols`, fonts/cursors | Always on | baseline |
| Offline image updates | Disabled by default | `-UpdateImage Stable25H2` opts in; `-UpdatePayloadRoot <dir>` overrides the cache root |

Surface driver handling is intentionally conservative. For exact Surface targets,
prefer `-DriverSource SurfaceCatalog -DriverPath <surface-device-id>` so WinMint
resolves the official Microsoft Download Center package, downloads it into the
temp build workspace, verifies Microsoft ownership/signature evidence, extracts
the MSI, and injects only the safe offline subset. Manual official Surface MSI
input remains available with `-DriverSource SurfaceMsiSafe -DriverPath <Surface.msi>`.
Both paths require the `SurfaceUpdate` payload, exclude firmware-class drivers
from offline injection, and write driver include/defer decisions to
`WinMint-DriverInventory.json`. Generic `Custom` driver injection remains
available for non-Surface packs, but it is not the recommended path for Surface
recovery-critical installs.

Raycast is installed through the Microsoft Store source when selected. Its
Everything backend stays local and quiet: amd64/x86-64 builds use the winget
Everything Beta package, while ARM64 builds use a pinned native upstream
Everything 1.5 ARM64 installer with SHA256 verification.

On DMA builds, Windows exposes Edge as an uninstallable normal application.
Without `-KeepEdge`, WinMint requests Edge removal and first attempts the
supported Edge app uninstaller. If that normal uninstall path leaves browser
files behind, WinMint reports that as an incomplete supported uninstall rather
than applying ownership hacks or hidden cleanup switches. WebView2, Store,
winget, and Windows Update are preserved.

### Stable 25H2 Pre-Update Payloads

WinMint can pre-service the user-provided Microsoft ISO with explicit offline
payloads so first logon has less left to update. This is profile-backed and
opt-in because it downloads large payloads and materially increases build time:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 new .\BuildProfile.json `
  -SourceIso .\Win11_25H2_English_Arm64.iso `
  -Architecture arm64 `
  -UpdateImage Stable25H2 `
  -UpdatePayloadRoot D:\WinMintPayloads\25H2-BRelease
```

If `-UpdatePayloadRoot` is omitted, generated profiles use the default cache
root under `%TEMP%\Win11ISO_dependency_cache\updates\25H2-BRelease`. On real
builds, WinMint populates that root from official Microsoft sources before
preflight: Microsoft Update Catalog for cumulative/checkpoint updates, Setup
Dynamic Update and Safe OS Dynamic Update payloads, and matching .NET payloads
when Microsoft publishes them, plus Microsoft's Defender offline image update
endpoint for Defender. Microsoft Update Catalog downloads must carry Catalog
SHA256 metadata and are verified before DISM sees them. The payload root is
reviewable and deterministic:

```text
25H2-BRelease\
  packages\            # Patch Tuesday quality/security .msu/.cab payloads
  dynamic-update\      # Windows Setup / Safe OS dynamic update .msu/.cab payloads
  defender\            # Defender offline image update .cab/.msu payloads
  dotnet\              # .NET cumulative update .msu/.cab payloads
  appx\                # Store/MSIX bundles such as Windows Terminal/App Installer
  appx-dependencies\   # Dependency .appx/.msix files, optionally under x64\ or arm64\
  UpdatePayloadManifest.json
```

`Stable25H2` means broad Windows 11 25H2 Patch Tuesday/B-release payloads only.
The offline `install.wim` servicing path applies the OS quality/security chain
and matching .NET payloads when available. Setup/Safe OS Dynamic Update payloads
and Defender offline image payloads are acquired and reported, but are not fed
to mounted `install.wim` as generic OS packages. WinMint rejects optional
preview intent and does not apply device-specific drivers, firmware, or OEM
payloads through this path. Store app catch-up is live user work: FirstLogon
runs `winget upgrade --all` with package/source agreement acceptance and records
the command logs in the agent state.

Local-account builds are fully unattended: the computer name comes from the
profile, the password is injected into the profile, and OOBE hides the network
page instead of stopping for personal/work setup.

## Guardrails

- Left intact: Defender, Firewall, SmartScreen, Windows Update, Store, WebView2
  runtime, WSL, IPv6, WinRE, UAC, and the component store.
- Never patches `IntegratedServicesRegionPolicySet.json`.
- Leaves no recurring maintenance task or background service behind.
- Destructive disk modes and USB writes are explicit and opt-in.

## Requirements

- Windows 11 build host, PowerShell 7.6.2+, Administrator rights for real builds.
- Windows 11 25H2+ source ISO and about 25 GB of free scratch space.
- `oscdimg.exe` from the Windows ADK (installed manually or through WinMint).
- A `dism.exe` at least as new as the source image build. WinMint fails early
  with guidance if the host or ADK DISM is older.

## Common commands

```powershell
# Validate repository syntax and contracts
pwsh -NoProfile -File tools\validation\Validate.ps1

# Validate a packaged release launch path after building apps\gui\bin\WinMint-GUI.exe
pwsh -NoProfile -File tools\validation\Validate.ps1 -RunReleaseSmoke

# Build from a saved profile
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 build .\BuildProfile.json

# Build, then write a UEFI-only USB installer
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 `
  build .\BuildProfile.json -WriteUsb -Disk 3 -ConfirmDisk 3

# Hyper-V test loop helpers
pwsh -NoProfile -File .\tools\vm\New-WinMintHyperVProfile.ps1 -OutPath .\output\hyper-v.json -SourceIso .\tests\fixtures\iso\official-win11-25h2-english-arm64-v2.iso
pwsh -NoProfile -File .\tools\vm\Build-And-TestVm.ps1 -ProfilePath .\tests\profiles\hyper-v-install-arm64.json
```

Hyper-V acceptance profiles intentionally target Windows 11 Pro with the Pro
generic key because Enhanced Session testing depends on Pro. A Home-only ISO is
not a valid source for the VM test profile.

> USB writing is post-build and destructive. WinMint targets UEFI-only GPT media
> with an NTFS install partition (avoiding the FAT32 4 GB `install.wim` limit),
> using [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs) by Pete Batard (GPL-2.0)
> to boot installation media from NTFS.

## Contracts

| Contract | Purpose |
|----------|---------|
| `BuildProfile.json` | Build intent from GUI, CLI, or automation |
| `BuildManifest.json` | Machine-readable record of what the engine did |
| `BuildDelta.json` | Generated backend audit of what WinMint intends to change and stage |
| `state.json` | FirstLogon agent retry and resume state |

Schemas live in [`schemas/`](schemas).

## Release readiness

The public launch path is `irm https://winmint.yanai.sh | iex`. Public-ready
releases must pass the release readiness gates in
[`docs/Release-Readiness.md`](docs/Release-Readiness.md), backed by
[`config/release-readiness.json`](config/release-readiness.json).

Hardware acceptance is tracked separately because VM and dry-run coverage cannot
prove Surface firmware/driver, Copilot-key, and live desktop behavior. The
inventory lives in [`config/hardware-acceptance.json`](config/hardware-acceptance.json)
and the runbook lives in [`docs/Hardware-Acceptance.md`](docs/Hardware-Acceptance.md).

## Documentation

- [Project structure](docs/Project-Structure.md)
- [Distribution](docs/Distribution.md)
- [Debloat strategy](docs/Windows-Debloat-Strategy.md)
- [Hardware acceptance](docs/Hardware-Acceptance.md)

## License

WinMint is licensed under GPL-2.0-or-later; see [LICENSE](LICENSE). Bundled
third-party assets retain their original licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
