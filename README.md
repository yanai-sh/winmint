# WinMint

Opinionated Windows 11 ISO builder for clean developer workstation installs.
The primary target is Windows 11 Home / Home Single Language / en-US.

WinMint starts from the Windows ISO you provide, applies a focused workstation
baseline, stages setup/first-logon automation, and emits a bootable ISO. It does
not ship or pin a hidden golden Windows image.

## Quick Start

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-GUI.ps1
```

Remote launcher:

```powershell
irm https://winmint.yanai.sh | iex
```

Headless dry run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 -DryRun
```

## Entry Points

| Entry point | Purpose |
|-------------|---------|
| `WinMint-GUI.ps1` | Primary GPUI launcher |
| `WinMint-CLI.ps1` | Headless/profile-driven build entry |
| `winmint.ps1` | Download/verify/launch latest release |

## Requirements

- Windows 11 build host
- PowerShell 7.3+
- Administrator rights for real ISO builds
- Windows 11 25H2+ source ISO
- About 25 GB free scratch space
- `oscdimg.exe` from the Windows ADK, installed manually or through WinMint
- A DISM engine at least as new as the source ISO image build. If the host/ADK
  `dism.exe` is older, WinMint fails before servicing and tells you the image
  build, DISM build, and whether to install a newer ADK/host DISM or use an
  older source ISO.

## Common Commands

```powershell
# Validate repository syntax and contracts
pwsh -NoProfile -File tools\validation\Validate.ps1

# Smoke-test profile invariants
pwsh -NoProfile -File tests\contract\Test-ProfileInvariants.ps1

# Build from an existing profile
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 `
  -ProfilePath .\BuildProfile.json

# Build and then write a UEFI-only USB installer
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 `
  -ProfilePath .\BuildProfile.json `
  -WriteUsb -UsbDiskNumber 3 -ConfirmUsbDiskNumber 3

# Write an already-built ISO to USB
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\media\New-WinMintUsbInstaller.ps1 `
  -IsoPath .\output\WinMint.iso `
  -UsbDiskNumber 3 `
  -ConfirmUsbDiskNumber 3

# Create a release bundle
pwsh -NoProfile -File tools\release\New-WinMintReleaseBundle.ps1 -Version v0.2.0
```

## Repository Layout

```text
apps/       Primary GPUI front end
crates/     Rust contract helpers and small CLI tools
src/        Engine, FirstLogon agent, and Windows Setup payloads
tools/      Validation, release, bridge, and authoring tools
tests/      Contract tests and local fixture roots
config/     Product policy and release manifests
schemas/    JSON contracts
assets/     Brand, runtime payloads, and UI presentation assets
docs/       Architecture, distribution, UI, and debloat rationale
```

## Contracts

WinMint has three first-class JSON contracts:

| Contract | Purpose |
|----------|---------|
| `BuildProfile.json` | User/build intent from GUI, CLI, or automation |
| `BuildManifest.json` | Machine-readable record of what the engine did |
| `state.json` | FirstLogon agent retry/resume state |

Schemas live in `schemas/`.

## Product Guardrails

- The user-provided ISO is the serviced Windows source.
- Defender, Firewall, SmartScreen, Windows Update, Store infrastructure,
  WebView2, WSL, IPv6, WinRE, UAC, and the component store stay intact.
- Debloat policy is profile-group based, not a matrix of granular toggles.
- DMA interoperability is enabled by default and uses Ireland only as an
  internal setup latch.
- Location services are enabled by default for laptop usefulness; they can be
  explicitly disabled with `-NoLocationServices`.
- WinMint does not leave behind a recurring maintenance task or background
  drift-fighting service.
- Destructive disk modes are explicit.
- USB installer creation is optional and explicitly destructive. WinMint uses
  modern UEFI-only GPT media with an NTFS install partition.

## Build Profiles

WinMint exposes simple build intents instead of a debloat dashboard. The
baseline profile is `Minimal`; additive groups are `Developer`, `CopilotPlus`,
`Gaming`, and `DesktopUI`. CLI spellings are `-Developer`, `-Copilot`,
`-Gaming`, and `-DesktopUI`.

`CopilotPlus` means a Copilot+ PC hardware-aware profile with an AI-free
WinMint posture. It removes provisioned Copilot/WebExperience-style AI AppX
packages, removes supported AI optional features such as Recall when present,
and applies Windows, Edge, Notepad, Paint, and App Privacy AI policies. This is
serviceable removal: WinMint does not remove Edge, WebView2, Store
infrastructure, winget, Windows Update, component-store metadata, or protected
CBS packages.

## DMA Interoperability

DMA interop is on by default. WinMint uses Ireland internally during Windows
Setup: `Ireland`, `en-IE`, GeoID `68`. This is a fixed internal setup region,
not a user choice. CLI users can opt out with `-NoDmaInterop`.

At the start of FirstLogon, before optional user setup modules run, WinMint
restores the configured user region, locale, time zone, and location-services
posture. Location services can remain enabled and use the real device location;
DMA interop does not require leaving the visible user region set to Ireland.
Automatic time-zone updates stay disabled by default to avoid Windows drifting
the restored time zone after setup.

Because the DMA setup latch already reduces some Microsoft default-app and
promotion pressure, WinMint keeps the default AppX cleanup catalog focused:
Microsoft consumer apps, communication apps, gaming apps, Copilot/WebExperience,
and AI surfaces. Broad third-party and OEM prefixes remain cataloged as
candidate-only drift coverage for unusual ISOs, but they are not part of the
normal DMA-on default removal surface.

## Documentation

- [Project structure](docs/Project-Structure.md)
- [Distribution](docs/Distribution.md)
- [Debloat strategy](docs/Windows-Debloat-Strategy.md)

## USB Installers

WinMint can optionally write the completed ISO to a USB installer so users do
not need a separate Rufus step. USB writing is post-build: the ISO is still the
primary build artifact.

The USB writer targets modern Windows systems: GPT, UEFI-only boot, an NTFS
install partition, and a tiny UEFI:NTFS helper partition. This avoids FAT32's
4 GB file limit for large `sources\install.wim` files while preserving the
normal Windows installer layout.

When creating UEFI-only USB installers with an NTFS install partition, WinMint
downloads and verifies UEFI:NTFS by Pete Batard to boot Windows installation
media from NTFS on firmware that only provides FAT/FAT32 boot support.

UEFI:NTFS is developed by the Rufus project author and is licensed separately
under GPL-2.0. Source and license: https://github.com/pbatard/uefi-ntfs

## License

WinMint is licensed under GPL-2.0-or-later. See [LICENSE](LICENSE).

Bundled third-party assets retain their original licenses. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
