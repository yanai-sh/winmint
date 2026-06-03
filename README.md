<div align="center">

<img src="assets/brand/winmint_hero.png" alt="WinMint" width="540">

Windows 11 ISO builder for clean developer workstation installs.

[![License](https://img.shields.io/badge/License-GPL--2.0--or--later-3ABf7c?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%2011%2025H2%2B-0078D6?style=flat-square&logo=windows11&logoColor=white)](#requirements)
[![PowerShell](https://img.shields.io/badge/PowerShell-7.3%2B-5391FE?style=flat-square&logo=powershell&logoColor=white)](#requirements)
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

# Headless dry run (read-only; no WIM mount or disk writes)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 -DryRun
```

```powershell
# Remote launcher (downloads, verifies, and launches the latest release)
irm https://winmint.yanai.sh | iex
```

| Entry point | Purpose |
|-------------|---------|
| `WinMint-GUI.ps1` | GPUI launcher |
| `WinMint-CLI.ps1` | Headless and profile-driven builds |
| `winmint.ps1` | Download, verify, and launch the latest release |

## What it builds

WinMint uses a subtractive default plus a small set of opt-in keep flags, not a
debloat dashboard. The default build removes everything and folds the developer
quality-of-life tweaks (Developer Mode, PowerShell RemoteSigned, .NET and
PowerShell telemetry opt-out, elevated-terminal menu, OpenSSH) into the baseline.

| Domain | Default | Opt-in flag |
|--------|---------|-------------|
| AI / Copilot / Recall | Full serviceable removal | `-KeepCopilot` keeps all Copilot+ AI; Recall stays removed |
| Edge browser | Removed via DMA uninstall | `-KeepEdge` keeps Edge; debloat applies either way |
| Xbox / Game Bar | Removed | `-KeepGaming` keeps gaming apps and performance tweaks |
| Shell layers | Off | `-DesktopUI` adds Windhawk, YASB, Komorebi |
| Dev tweaks and OpenSSH | Always on | baseline |

Edge browser removal uses the DMA-supported in-OS uninstall, run during setup
while the device is still in the EEA region. It is skipped and logged when DMA
interop is off (`-NoDmaInterop`). The Edge and WebView2 runtime, Store, winget,
and Windows Update are always preserved.

## Guardrails

- Left intact: Defender, Firewall, SmartScreen, Windows Update, Store, WebView2
  runtime, WSL, IPv6, WinRE, UAC, and the component store.
- Never patches `IntegratedServicesRegionPolicySet.json`.
- Leaves no recurring maintenance task or background service behind.
- Destructive disk modes and USB writes are explicit and opt-in.

## Requirements

- Windows 11 build host, PowerShell 7.3+, Administrator rights for real builds.
- Windows 11 25H2+ source ISO and about 25 GB of free scratch space.
- `oscdimg.exe` from the Windows ADK (installed manually or through WinMint).
- A `dism.exe` at least as new as the source image build. WinMint fails early
  with guidance if the host or ADK DISM is older.

## Common commands

```powershell
# Validate repository syntax and contracts
pwsh -NoProfile -File tools\validation\Validate.ps1

# Build from a saved profile
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 -ProfilePath .\BuildProfile.json

# Build, then write a UEFI-only USB installer
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 `
  -ProfilePath .\BuildProfile.json -WriteUsb -UsbDiskNumber 3 -ConfirmUsbDiskNumber 3
```

> USB writing is post-build and destructive. WinMint targets UEFI-only GPT media
> with an NTFS install partition (avoiding the FAT32 4 GB `install.wim` limit),
> using [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs) by Pete Batard (GPL-2.0)
> to boot installation media from NTFS.

## Contracts

| Contract | Purpose |
|----------|---------|
| `BuildProfile.json` | Build intent from GUI, CLI, or automation |
| `BuildManifest.json` | Machine-readable record of what the engine did |
| `state.json` | FirstLogon agent retry and resume state |

Schemas live in [`schemas/`](schemas).

## Documentation

- [Project structure](docs/Project-Structure.md)
- [Distribution](docs/Distribution.md)
- [Debloat strategy](docs/Windows-Debloat-Strategy.md)

## License

WinMint is licensed under GPL-2.0-or-later; see [LICENSE](LICENSE). Bundled
third-party assets retain their original licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
</content>
