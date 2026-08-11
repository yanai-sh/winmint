<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/brand/readme/dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/brand/readme/light.svg">
    <img src="assets/brand/readme/light.svg" alt="WinMint" width="720">
  </picture>
</div>

ARM64-first Windows 11 ISO builder for clean developer workstation installs.
You supply the official Microsoft ISO. WinMint does not download or redistribute Windows ([ADR-001](docs/decisions/ADR-001-source-iso-legal.md)).

## What you get

- Start with a profile that describes the Windows install you want
- Turn that profile into a bootable Windows ISO
- Service the ISO offline, then finish live-user setup on first sign-in
- Supply your own [Windows 11 ISO from Microsoft](https://www.microsoft.com/software-download/windows11)
- Browse [sample profiles and their wipe risk](samples/README.md) before you build

## Status

WinMint is Alpha. You can plan and build ISOs today. A full wipe install (USB → WinPE → OOBE → FirstLogon) is something you run on your own hardware; land the results in the repo when you have them. Gate B (`just primary-gate`) is pre-wipe ISO evidence only — it is not the same as a completed install.

## Quickstart

No git clone and no source zip. On Windows (ARM64 recommended), in PowerShell:

```powershell
irm https://winmint.yanai.sh | iex
```

That downloads a **verified toolkit** release (SHA-256 checked), then opens the Wizard. The default session is temporary and is deleted when the Wizard exits.

Keep a durable toolkit for ISO builds (opt-in cache under `%LOCALAPPDATA%\WinMint\versions\<tag>`, or pass `-InstallRoot`):

```powershell
& ([scriptblock]::Create((irm https://winmint.yanai.sh))) -CacheRelease -NoLaunch
cd $env:LOCALAPPDATA\WinMint\versions\v0.1.0   # use the tag you installed
just plan   # optional minutes-scale first win (no Source ISO)
```

Headless Cli needs a profile (and a Source ISO for builds). First win without an ISO:

```powershell
& ([scriptblock]::Create((irm https://winmint.yanai.sh))) -Headless -ValidateOnly -ProfilePath samples\smoke.profile.json -CacheRelease
```

Bare `irm https://winmint.yanai.sh/cli | iex` forwards to headless build and requires `-ProfilePath` and `-SourceIso`.

Needs network once, plus PowerShell 7.6+ and [Just](https://github.com/casey/just#installation) (the bootstrap installs them via winget when missing). Building an ISO later still needs a Microsoft Source ISO, an administrator session, and several hours of offline image servicing.

## Build a wipe ISO

From a **durable** toolkit (`-CacheRelease` / `-InstallRoot` above) or a contributor checkout, use `samples/sl7.profile.json`. It expects a lab password and shows the OOBE Wi‑Fi page — stay nearby for network setup ([SECRETS](docs/design/SECRETS.md)).

```powershell
cd $env:LOCALAPPDATA\WinMint\versions\v0.1.0   # or your InstallRoot / clone
New-Item -ItemType Directory -Force -Path .scratch | Out-Null
Set-Content -Path .scratch/sl7.password -Value 'your-lab-password' -NoNewline
just primary-gate ISO=path\to\source.iso
# Watch progress in another terminal (stages can sit for a long time with no % complete):
just watch-apply WORK=.scratch/sl7-primary
```

When it finishes, flash `.scratch/sl7-primary\out.iso` to a UEFI USB with **Rufus** in **DD Image** mode (not ISO mode). Check the ISO SHA-256 against the `outputIso.sha256` entry under `digests` in `.scratch/sl7-primary\evidence.json` before you wipe. Boot expects WinPE LaunchApply, not Setup.

`just primary-gate` builds the wipe ISO (`Release`, package-strict). Keep it in `.scratch/sl7-primary` — do not flash a Test build from `.scratch/sl7-build`. Soft `just metal QUALITY=Release` is rejected; wipe media is primary-gate only.

For iterative Test builds only: `just metal ISO=path\to\source.iso` (default workdir `.scratch/sl7-build`). That path is not the wipe gate.

Before you wipe a machine, prepare a restore path for that PC: OEM recovery when available, or a Windows recovery drive. WinMint does not download or ship recovery images.

<details>
<summary>From source (contributors)</summary>

```powershell
git clone https://github.com/yanai-sh/winmint.git
cd winmint
winget install Casey.Just
# .NET 11 preview SDK — see global.json
just wizard
just plan
just pack-release v0.0.0-local
```

</details>

[Issues](https://github.com/yanai-sh/winmint/issues) · [GPL-3.0-or-later](LICENSE)
