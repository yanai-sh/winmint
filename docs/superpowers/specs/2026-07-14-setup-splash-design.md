# 2026-07-14 FirstLogon Provisioning Splash Design Spec

## 1. Goal & Context
During the WinMint `FirstLogon` phase, the system engages a **provisioning lock** via a native AOT application (`WinMintSetupShell.exe` in splash mode) to shield the desktop and disable user input while installing setup packages. 

The goal of this change is to upgrade the splash screen from a silent black screen with a single sliding line to a themed, high-fidelity loading screen. The splash must communicate overall progress, active task detail, remaining steps, and elapsed time using the WinMint design tokens.

---

## 2. Proposed Visual Improvements

### A. Themed Background
* **Direct2D (`SplashPainter.cs`)**: Clear the screen with `tokens.Canvas` (`#11161d` or parsed value) instead of solid black (`#000000`).
* **GDI Fallback (`GdiFallbackPainter.cs`)**: Parse and clear with `tokens.Canvas` (translating `#11161d` to GDI hex).

### B. Progress Bar (Determinate vs Indeterminate)
* **Track**: Rendered with width `160f` at `0.60 * height` (or stacked layout position) using `tokens.ProgressTrack` (`#2e3036`).
* **Fill**: Rendered with `tokens.Accent` (`#0067c0`).
* **Logic**:
  * If `status.ProgressMode == "determinate"`, draw the filled segment using the ratio of `status.ProgressPct` (0 to 100).
  * If `status.ProgressMode == "indeterminate"`, fall back to the existing sliding animated block (25% segment width scrolling across the track).

### C. Centered Informational Column
The layout stack starts at the progress bar and flows downwards:
1. **Progress Bar**: Drawn centered horizontally at `y = 0.60 * height`.
2. **Group Label**: Uppercase, small, semi-bold (e.g. `INSTALLING TOOLS`), drawn using `_groupFormat` with color `tokens.Muted` (`#b7c0cc`) at `y = 0.64 * height`.
3. **Task Label**: Regular weight, larger font size (e.g. `Installing Winget package: windhawk`), drawn using `_taskFormat` with color `tokens.Ink` (`#f4f7fb`) at `y = 0.68 * height`.
4. **Step List**: Render remaining non-done steps below the task label at `y = 0.72 * height`:
   * Current step is drawn with full opacity using `tokens.Ink`.
   * Future/pending steps are drawn with `0.38f` opacity using `tokens.Dim` (`#8792a1`).
5. **Meta Line**: Render `PresetName · MM:SS elapsed` using `_bannerFormat` at the bottom of the screen (`height - tokens.Layout.DockPaddingBottom`) using color `tokens.Dim` at `0.72f` opacity.

---

## 3. Component Modifications

### `apps/setup-shell/SplashPainter.cs`
* Modify `Paint` to clear target using `tokens.Canvas`.
* Implement determinate progress bar logic.
* Call `DrawStepList` and position it in the vertical stack.
* Draw `GroupLabel` and `TaskLabel` using the compiled text formats.
* Draw the meta footer string returned by `FormatShellMeta`.

### `apps/setup-shell/GdiFallbackPainter.cs`
* Modify `Paint` to clear using GDI brush of `tokens.Canvas`.
* Draw a simple GDI progress bar rectangle for determinate progress.
* Draw Group, Task, Steps, and Meta text using `DrawLine`.

### `tests/setup-shell/Test-WinMintSetupShell.ps1`
* Correct the bug on line 53 where `-ExePath $nativeExe` is passed instead of the defined `$hostExe` variable.

---

## 4. Verification Plan

### Automated Verification
Run the setup shell linter and tests:
```powershell
pwsh -NoProfile -File tests/setup-shell/Test-WinMintSetupShell.ps1
```

### Local Visual Demo (Host)
Compile and launch the preview directly on the local Windows desktop:
```powershell
pwsh -NoProfile -File tools\release\Build-WinMintSetupShell.ps1
pwsh -NoProfile -File tools\dev\Show-WinMintSplash.ps1 -Native
```
Verify that all text labels, step lists, elapsed time, progress modes, and themed background display correctly and scale gracefully on the host monitor.
