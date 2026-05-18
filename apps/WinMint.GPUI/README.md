# WinMint GPUI

Primary GPUI front end for the WinMint ISO builder.

GPUI owns the graphical source-selection shell and writes transient UI intent to:

```text
output\gpui\ui-intent.json
```

The PowerShell bridge converts that intent into the engine contract:

```text
output\gpui\BuildProfile.json
```

Release users start GPUI through the root launcher:

```powershell
pwsh -NoProfile -File WinMint-GUI.ps1
```

The launcher expects the packaged binary at:

```text
apps\WinMint.GPUI\bin\WinMint-GUI.exe
```

## Development

Install a current Rust toolchain, then run from the repository root:

```powershell
pwsh -NoProfile -File tools\gpui\Start-GpuiLab.ps1
```

To compare against the plain system titlebar:

```powershell
pwsh -NoProfile -File tools\gpui\Start-GpuiLab.ps1 -SystemTitlebar
```

To verify compilation without launching the window:

```powershell
pwsh -NoProfile -File tools\gpui\Start-GpuiLab.ps1 -BuildOnly
```

Build the release binary with:

```powershell
pwsh -NoProfile -File tools\release\Build-WinMintGpui.ps1
```

After clicking `Write intent`, create and validate the real profile:

```powershell
pwsh -NoProfile -File tools\gpui\New-GpuiLabBuildProfile.ps1 -DryRun
```

Run the dry run from an elevated shell, or add `-AllowElevate` for the same explicit UAC handoff used by the CLI.
