# 2026-07-14 FirstLogon Provisioning Splash Design Spec

## 1. Goal & Context
During the WinMint `FirstLogon` phase, the system engages a **provisioning lock** via a native AOT application (`WinMintSetupShell.exe` in splash mode) to shield the desktop and disable user input while installing setup packages. 

The goal of this change is to upgrade the splash screen from a silent black screen with a single sliding line to a themed, high-fidelity loading screen. The splash must communicate overall progress, active task detail, remaining steps, and elapsed time using the WinMint design tokens.

---

## 2. Proposed Visual Improvements

### A. Fluent Gradient Background (Direct2D Only)
Instead of clearing the screen with a solid flat color, we paint a rich Fluent-style gradient:
1. **Linear Base**: A linear gradient flowing vertically from `#080a0e` (dark onyx) at `offset 0.0` to `tokens.Canvas` (mica canvas `#11161d`) at `offset 1.0`.
2. **Radial Accent Flare**: A radial gradient center-aligned behind the pulsing logo at `(50% width, 38% height)`. It uses `tokens.Accent` at `0.12` opacity in the center, falling off to transparent (`0.0` opacity) at `offset 0.75` (radius X: `0.80 * width`, radius Y: `0.50 * height`).
* **GDI Fallback**: Clear with a solid brush of `tokens.Canvas` (translated GDI hex) for simplicity.

### B. Segoe UI Variable Font Resolution
DirectWrite `CreateTextFormat` requires a specific font family name. We will dynamically check system font availability to prefer the modern Windows 11 font:
1. `"Segoe UI Variable Text"`
2. `"Segoe UI Variable"`
3. Configured `tokens.FontFamily` (usually `"Segoe UI"`)
4. Fallback: `"Segoe UI"`

### C. Natural Layout Hierarchy (Progress Bar below active text)
To match standard user reading hierarchy (Phase -> Active Task -> Task Progress -> Details -> Footer), we re-arrange the vertical coordinates:
1. **Pulsing Logo**: Centered horizontally at `y = 0.35 * height` (pulsing scale).
2. **Group Label**: Uppercase, small, semi-bold (e.g. `INSTALLING TOOLS`), drawn using `_groupFormat` with color `tokens.Muted` (`#b7c0cc`) at `y = 0.52 * height`.
3. **Task Label**: Regular weight, larger font size (e.g. `Installing Winget package: windhawk`), drawn using `_taskFormat` with color `tokens.Ink` (`#f4f7fb`) at `y = 0.56 * height`.
4. **Progress Bar**: Centered horizontally at `y = 0.63 * height` (track width `160f` using `tokens.ProgressTrack` and fill using `tokens.Accent`):
   * Determinate or indeterminate mode depending on `status.ProgressMode`.
5. **Step List**: Render remaining non-done steps starting at `y = 0.67 * height`:
   * Current step is drawn with full opacity using `tokens.Ink`.
   * Future/pending steps are drawn with `0.38f` opacity using `tokens.Dim` (`#8792a1`).
6. **Meta Line**: Render `PresetName · MM:SS elapsed` using `_bannerFormat` at `y = height - tokens.Layout.DockPaddingBottom` (color `tokens.Dim` at `0.72f` opacity).

---

## 3. Component Modifications

### `apps/setup-shell/SplashPainter.cs`
* Modify `Paint` to create and apply the linear and radial background gradient brushes.
* Adjust layout coordinates to place progress bar at `0.63 * height` (below task labels).
* Draw `GroupLabel` and `TaskLabel` at `0.52 * height` and `0.56 * height` respectively.

### `apps/setup-shell/SetupShellHost.cs`
* Implement `ResolveFontFamily` helper probing system font collection.
* Compile text formats using the resolved font family name.
* Dispose of background linear/radial D2D brushes appropriately if cached, or construct them per-frame/recreate-target.

### `apps/setup-shell/GdiFallbackPainter.cs`
* Clear background to solid `tokens.Canvas`.
* Draw text stack using the updated layout coordinates.
* Draw progress bar below the task text at `0.63 * height`.

---

## 4. Verification Plan

### Automated Verification
```powershell
pwsh -NoProfile -File tests/setup-shell/Test-WinMintSetupShell.ps1
pwsh -NoProfile -File tools\dev\Invoke-WinMintPesterContract.ps1
```

### Local Visual Demo (Host)
Compile and launch preview:
```powershell
pwsh -NoProfile -File tools\release\Build-WinMintSetupShell.ps1
pwsh -NoProfile -File tools\dev\Show-WinMintSplash.ps1 -Native
```
Verify the Fluent gradient glow behind the pulsing logo, the Segoe UI Variable typeface scaling, and the improved layout order.
