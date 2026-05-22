# WinMint GUI

Primary Rust/GPUI front end for the WinMint ISO builder.

The GUI owns the graphical source-selection shell and writes transient UI intent to:

```text
output\gui\ui-intent.json
```

The PowerShell bridge converts that intent into the engine contract:

```text
output\gui\BuildProfile.json
```

Profile intent shaping is shared with command-line tooling through the Rust
core crate at `crates\winmint-core`. Keep GUI-only rendering in this app, and
put reusable contract normalization in the core crate.

Release users start the GUI through the root launcher:

```powershell
pwsh -NoProfile -File WinMint-GUI.ps1
```

The launcher expects the packaged binary at:

```text
apps\gui\bin\WinMint-GUI.exe
```

## Development

Install a current Rust toolchain, then run from the repository root:

```powershell
pwsh -NoProfile -File tools\gui\Start-GuiDev.ps1
```

To compare against the plain system titlebar:

```powershell
pwsh -NoProfile -File tools\gui\Start-GuiDev.ps1 -SystemTitlebar
```

To verify compilation without launching the window:

```powershell
pwsh -NoProfile -File tools\gui\Start-GuiDev.ps1 -BuildOnly
```

Build the release binary with:

```powershell
pwsh -NoProfile -File tools\release\Build-WinMintGui.ps1
```

After clicking `Write intent`, create and validate the real profile:

```powershell
pwsh -NoProfile -File tools\gui\New-GuiBuildProfile.ps1 -DryRun
```

Run the dry run from an elevated shell, or add `-AllowElevate` for the same explicit UAC handoff used by the CLI.
