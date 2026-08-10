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
- Service the ISO offline, then finish live-user setup with the FirstLogon Provisioning Supervisor
- Supply your own [Windows 11 ISO from Microsoft](https://www.microsoft.com/software-download/windows11)
- Browse [sample profiles and their wipe risk](samples/README.md) before you build

## Status

WinMint is Alpha. Hyper-V Smoke runs against a real source ISO. The command-line interface is primary; `just wizard` is optional. Primary wipe is a maintainer gate in [#96](https://github.com/yanai-sh/winmint/issues/96), not general availability.

## Try in 5 minutes

You can explore WinMint without a source ISO. Start the Wizard, or validate and plan the smoke sample:

```powershell
just wizard
# Or validate and plan the default smoke sample:
just plan
```

## Build later

Building needs a [Windows 11 ISO from Microsoft](https://www.microsoft.com/software-download/windows11), an administrator session, .NET 11 preview SDK, and `pwsh` 7.6+.
Offline Deployment Image Servicing and Management (DISM) work takes multiple hours.

```powershell
just primary-gate ISO=path\to\source.iso
```

`primary-gate` creates the wipe ISO with `Release` quality and package-strict checks. Use `just metal ISO=path\to\source.iso` for iterative Test Gate B work; it stays `Test` and does not replace the primary wipe gate.

Before you wipe a machine, prepare a restore path for that PC: OEM recovery when available, or a Windows recovery drive. WinMint does not download or ship recovery images.

<details>
<summary>Maintainer</summary>

- Run `just check` for unit tests, the fake elevated runner, and servicing analysis. It does not use an ISO or DISM.
- Watch an active Apply with `just watch-apply WORK=.scratch/sl7-build`. `STALL_SUSPECT` belongs to Smoke VM evidence only, never Apply.
- Run `just exclude-scratch` from an administrator session to exclude `.scratch` and servicing work from Defender scanning.
- Use `just clean-artifacts` after Apply or Smoke campaigns. It keeps one work directory and two ISOs under `.scratch`; `just wipe-scratch` removes all scratch artifacts. Do not run either during Apply or Smoke.

</details>

[Design](docs/DESIGN.md) · [Issues](https://github.com/yanai-sh/winmint/issues) · [GPL-3.0-or-later](LICENSE)
