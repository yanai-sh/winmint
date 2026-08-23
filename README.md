<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/brand/readme/dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/brand/readme/light.svg">
    <img src="assets/brand/readme/light.svg" alt="WinMint" width="720">
  </picture>
</div>

WinMint builds a custom Windows 11 ISO for a clean ARM64 developer PC.

You bring an [official Windows 11 ISO from Microsoft](https://www.microsoft.com/software-download/windows11). WinMint does not download or redistribute Windows. It services that ISO offline, then finishes setup on first sign-in.

## Alpha

You can plan and build ISOs today. Flashing that ISO and wiping a PC is something you run yourself. Treat every wipe as your own risk.

GitHub Releases are unsigned. See the [Code signing policy](docs/CODE_SIGNING.md).

## Open the Wizard

On Windows (ARM64 recommended), in PowerShell:

```powershell
irm https://winmint.yanai.sh | iex
```

This downloads a SHA-256-checked toolkit into a temporary folder and opens the Wizard. The toolkit is deleted when you quit. The work folder and output ISO stay on disk.

To check a sample profile without a Microsoft ISO:

```powershell
irm https://winmint.yanai.sh/validate | iex
```

The first run needs network. Missing PowerShell 7.6+ is installed from GitHub's MSI, not winget's MSIX (that package cannot service an image). Missing [Just](https://github.com/casey/just#installation) is installed via winget.

## Build the ISO

The Wizard is **Source** → **Account** → **Software** → **Review**.

1. Choose your Microsoft ISO.
2. Set a local account. A password is required.
3. Pick apps and cleanup, or continue with defaults.
4. On **Review**, choose **Build**. Servicing is elevated and takes several hours.

On Source, pick **Test** while you experiment. Pick **Release** when you intend to install from the ISO.

If you check **Require Wi-Fi during OOBE**, stay at the machine for network setup.

## Flash the USB

When **Build** finishes, Review shows the output ISO path and SHA-256. Check the hash before you wipe anything.

Write the ISO to a UEFI USB with [Rufus](https://rufus.ie/) in **DD Image** mode, not ISO mode. Boot expects WinPE LaunchApply, not Windows Setup.

Before you wipe a PC, prepare a restore path: OEM recovery when available, or a Windows recovery drive. WinMint does not download recovery images.

[Issues](https://github.com/yanai-sh/winmint/issues) · [Privacy](PRIVACY.md) · [GPL-3.0-or-later](LICENSE)
