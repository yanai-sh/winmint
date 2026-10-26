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

Registry scripts are the files in `post-install/registry/`. OneDrive, the inbox strip, and Surface drivers sit next to `Apply-LivePosture.ps1`. Each script also runs on its own from any folder. A second run leaves the same result. `Apply-LivePosture.ps1` finds its scripts next to itself, or under `registry\` beside it.

## Output ISO

The Output ISO is unstable. Do not write it to USB. Do not boot it. Do not install from it.

The metal goal is product-owned USB media that installs cleanly, with the curated settings still to come. The ISO compiler stays for Hyper-V/DVD acceptance. Its current output is unstable install media.

A build still takes an official **English (US)** Windows 11 **26H2** ARM64 ISO (family 26300) from [Microsoft’s ARM64 download](https://www.microsoft.com/en-us/software-download/windows11arm64) (English, not English International). A 25H2 ISO (family 26200) still services. WinMint does not download or redistribute Windows.

GitHub Releases are unsigned. See the [Code signing policy](docs/CODE_SIGNING.md).

[Issues](https://github.com/yanai-sh/winmint/issues) · [Privacy](PRIVACY.md) · [GPL-3.0-or-later](LICENSE)

Coding agents: [AGENTS.md](AGENTS.md) (map) · [CONTEXT.md](CONTEXT.md) (glossary).
