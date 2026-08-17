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

WinMint is Alpha. You can plan and build ISOs today. A full wipe install (USB → WinPE → OOBE → FirstLogon) is something you run on your own hardware; land the results in the repo when you have them. Gate B (`just primary-gate` / Wizard **Release → Build**) is pre-wipe ISO evidence only — it is not the same as a completed install.

GitHub Releases are unsigned. Authenticode is deferred. [Code signing policy](docs/CODE_SIGNING.md).

## Quickstart

No git clone and no source zip. On Windows (ARM64 recommended), in PowerShell:

```powershell
irm https://winmint.yanai.sh | iex
```

That downloads a **verified toolkit** (SHA-256 checked) into a **temporary session**, opens the Wizard, and removes the TEMP toolkit when the Wizard exits. That ephemerality is intentional — WinMint is session-shaped, not a standing install. ISO workdirs and the Output ISO still live on disk (they have to).

**First win without a Source ISO** (validate profile only — Alpha / ephemeral / no wipe):

```powershell
irm https://winmint.yanai.sh/validate | iex
```

Expect a clear validate result. Defaults to `samples/smoke.profile.json` (override with `?ProfilePath=…` if you want).

While the Wizard is open: select **Release** and **Build** to run Gate B wipe-media apply **in the Wizard** (workdir `%LOCALAPPDATA%\WinMint\work\gate-b`). Progress and Rufus DD / SHA flash guidance appear on Review when the Output ISO is ready.

**One-shot Gate B wipe ISO** (re-fetch toolkit, build Release+package-strict, delete TEMP toolkit, keep workdir):

```powershell
irm 'https://winmint.yanai.sh/primary-gate?SourceIso=C:\path\to\source.iso&ProfilePath=samples\sl7.profile.json' | iex
# Default workdir: %LOCALAPPDATA%\WinMint\work\gate-b
# URL-encode spaces in paths if needed.
```

Optional: `-CacheRelease` / `-InstallRoot` keep a reusable toolkit under `%LOCALAPPDATA%\WinMint\versions\<tag>` (power-user; not required).

<details>
<summary>Host prerequisites</summary>

Needs network once. Bootstrap installs GitHub MSI PowerShell 7.6+ (`PowerShell-*-win-arm64.msi` on ARM64 — not `winget Microsoft.PowerShell`, which is MSIX) and [Just](https://github.com/casey/just#installation) via winget when missing. Building an ISO needs a Microsoft Source ISO, an administrator session, and several hours of offline image servicing. ImageServicing may keep **Prepared media** under `%ProgramData%\WinMint\Servicing\` so a later Apply on the same Source ISO skips extraction; there is no `--reuse-media` switch. At most one Apply runs on the Host at a time.

</details>

## Build a wipe ISO

Prefer **Wizard Release → Build** (in-app Apply), **one-shot** `/primary-gate` above, or live `just primary-gate`. Use `samples/sl7.profile.json`. It expects a lab password and shows the OOBE Wi‑Fi page — stay nearby for network setup ([SECRETS](docs/design/SECRETS.md)).

```powershell
# From the live toolkit root (or after -NoLaunch left a TEMP toolkit folder):
# Password for samples/sl7 — create beside the workdir or under toolkit .scratch as SECRETS describes.
$work = Join-Path $env:LOCALAPPDATA 'WinMint\work\gate-b'
New-Item -ItemType Directory -Force -Path $work, .scratch | Out-Null
Set-Content -Path .scratch/sl7.password -Value 'your-lab-password' -NoNewline
just primary-gate ISO=path\to\source.iso
just watch-apply
# Default watch-apply workdir is Gate B ($work). Test lane: just watch-apply WORK=.scratch/sl7-build
```

Gate B workdir defaults to `%LOCALAPPDATA%\WinMint\work\gate-b` (same as `/primary-gate` and Wizard Release Build) so TEMP toolkit cleanup cannot delete the Output ISO. Flash that folder’s `winmint_sl7_Release_*.iso` (see `evidence.json` → `outputIsoPath`).

When it finishes, flash that Output ISO to a UEFI USB with **Rufus** in **DD Image** mode (not ISO mode). Check the ISO SHA-256 against the `outputIso.sha256` entry under `digests` in `evidence.json` before you wipe. Boot expects WinPE LaunchApply, not Setup. Gate B is still not a completed Primary install.

`just primary-gate` / `/primary-gate` / Wizard Release Build builds the wipe ISO (`Release`, package-strict). Soft `just host-apply QUALITY=Release` is rejected; wipe media is that Gate B path only.

For iterative Test builds only: `just host-apply ISO=path\to\source.iso` (default workdir `.scratch/sl7-build`). That path is not the wipe gate.

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
# Inspect the diagnostic plan files under .scratch/plan.
# jobs.json is the real guest wire; stages.json is a plan dump, not Apply input.
just pack-release v0.0.0-local
```

</details>

[Issues](https://github.com/yanai-sh/winmint/issues) · [GPL-3.0-or-later](LICENSE)
