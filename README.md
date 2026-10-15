<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/brand/readme/dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/brand/readme/light.svg">
    <img src="assets/brand/readme/light.svg" alt="WinMint" width="720">
  </picture>
</div>

WinMint is the maintainer's working tree. It is not ready for anyone else to run.

## Post-install

On an already-installed Windows 11 PC, the current path is [`post-install/`](post-install/Apply-LivePosture.ps1). Run it elevated, after Windows Update. The same files run under Windows PowerShell 5.1 and under PowerShell 7.

```powershell
cd post-install
powershell -NoProfile -File .\Apply-LivePosture.ps1 -DryRun
powershell -NoProfile -File .\Apply-LivePosture.ps1
```

`-DryRun` prints the planned changes and writes nothing. Pass `-Drivers` to include the Surface Laptop 7 ARM64 catalog MSI. Sign out after a real run. Language, time zone, UAC, Reserved Storage, and location stay as they are.

Each script also runs on its own: `Apply-Registry.ps1`, `Uninstall-OneDrive.ps1`, `Remove-InboxApps.ps1`, `Install-SurfaceDrivers.ps1`.

## Output ISO

The Output ISO is unstable. Do not write it to USB. Do not boot it. Do not install from it.

The goal is a portable ISO that installs cleanly, with the curated settings still to come. The compiler stays in the tree for that goal. Its current output is unstable install media.

A build still takes an official **English (US)** Windows 11 ARM64 ISO from [Microsoft software download](https://www.microsoft.com/software-download/windows11) (choose **English 64-bit**, not English International). WinMint does not download or redistribute Windows.

GitHub Releases are unsigned. See the [Code signing policy](docs/CODE_SIGNING.md).

[Issues](https://github.com/yanai-sh/winmint/issues) · [Privacy](PRIVACY.md) · [GPL-3.0-or-later](LICENSE)

Coding agents: [AGENTS.md](AGENTS.md) (map) · [CONTEXT.md](CONTEXT.md) (glossary).
