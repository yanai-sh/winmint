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
UI intent helpers live in `apps\gui\src\core`. Keep GUI-only rendering in this app, and
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

Install a current Rust toolchain. The fastest loop uses the cargo aliases in
`.cargo/config.toml` — run any of these from the repository root:

| Recipe | Does |
|---|---|
| `cargo gui` | Launch the GUI (custom titlebar) |
| `cargo gui-sys` | Launch with the OS titlebar (to compare chrome) |
| `cargo gui-build` | Compile the GUI without launching |
| `cargo gui-rel` | Release build + launch |
| `cargo checkw` | Fast type-check the whole workspace |
| `cargo lint` | `clippy` across the workspace |
| `cargo testw` | All Rust tests |
| `cargo core` | Core intent / bridge-contract tests only (fast) |

`cargo` works directly when `link.exe` is on PATH. If the MSVC linker isn't found
(e.g. ARM64 host needing the VS dev environment), use the PowerShell launcher
instead, which sets up VsDevCmd: `tools\gui\Start-GuiDev.ps1` (add `-SystemTitlebar`,
`-BuildOnly`, or `-Release`).

### Elevation (needed to read an ISO)

Mounting an ISO + DISM require admin. From a **non-admin** terminal, `-Elevate`
builds non-elevated (your `target\` stays user-owned) then launches the binary under
a single UAC prompt, so the ISO probe never re-prompts:

```powershell
pwsh -NoProfile -File tools\gui\Start-GuiDev.ps1 -Elevate
```

Plain `cargo gui` runs non-elevated and the ISO probe self-elevates per operation.
Running `cargo gui` from an **already-elevated terminal** avoids prompts and keeps app
logs in the console — the smoothest loop when debugging the probe.

### Testing operations

- **Probe an ISO without the GUI** (exercises the probe + UAC handoff, prints JSON):
  ```powershell
  pwsh -NoProfile -File tools\ui-bridge\Get-UiIsoMetadata.ps1 -Path <iso>
  ```
- **Inspect the intent the GUI wrote:** `Get-Content output\gui\ui-intent.json`
- **Intent → build profile pipeline** (uses the last GUI-written intent, validates it):
  ```powershell
  pwsh -NoProfile -File tools\gui\New-GuiBuildProfile.ps1 -DryRun
  ```
  Run from an elevated shell, or add `-AllowElevate` for the CLI's UAC handoff.
- **Release binary:** `pwsh -NoProfile -File tools\release\Build-WinMintGui.ps1`
