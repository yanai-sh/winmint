#Requires -Version 7.3
<#
<summary>
    Capture-UiScreenshot.ps1 — optional PNG capture for pixel-level visual review.

    Primary automation review uses Drive-Ui.ps1 -Action Snapshot (semantic JSON under
    output/ui-snapshots/). Use this script when you explicitly need a bitmap
    (layout, Mica, fonts). Saves to output/screenshots/<label>.png.

    Usage:
        # capture the current page with an auto label
        pwsh scripts/ui-automation/Capture-UiScreenshot.ps1

        # label the capture for a specific page
        pwsh scripts/ui-automation/Capture-UiScreenshot.ps1 -Page 0
        pwsh scripts/ui-automation/Capture-UiScreenshot.ps1 -Page page3-desktop

        # capture all pages by walking through Next clicks (manual: open the app
        # then run this once per page after navigating)
        pwsh scripts/ui-automation/Capture-UiScreenshot.ps1 -Page 1 ; pwsh scripts/ui-automation/Capture-UiScreenshot.ps1 -Page 2 ; ...

        # override window match (default: "WinMint")
        pwsh scripts/ui-automation/Capture-UiScreenshot.ps1 -WindowTitle 'Some other title'

    The window must be renderable. If it is minimized, the script shows it
    without activating it first. DwmGetWindowAttribute with
    DWMWA_EXTENDED_FRAME_BOUNDS is used so the saved PNG matches the app frame;
    `GetWindowRect` would include Windows 10/11 invisible drop-shadow padding
    and produce extra blank pixels around the window.
</summary>
#>

[CmdletBinding()]
param(
    [string]$Page,
    [string]$WindowTitle = 'WinMint',
    [string]$OutputDir,
    [Int64]$Hwnd = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

if (-not ('WinWS.ScreenshotInterop' -as [Type])) {
    Add-Type -Namespace WinWS -Name ScreenshotInterop -MemberDefinition @'
        [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
        public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

        [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto, SetLastError = true)]
        public static extern System.IntPtr FindWindow(string lpClassName, string lpWindowName);

        [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto)]
        public static extern int GetWindowText(System.IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool IsWindowVisible(System.IntPtr hWnd);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool IsIconic(System.IntPtr hWnd);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);

        [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
        public static extern bool GetWindowRect(System.IntPtr hWnd, out RECT lpRect);

        [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
        public static extern bool PrintWindow(System.IntPtr hwnd, System.IntPtr hdcBlt, uint nFlags);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool IsWindow(System.IntPtr hWnd);

        [System.Runtime.InteropServices.DllImport("dwmapi.dll")]
        public static extern int DwmGetWindowAttribute(System.IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);

        public delegate bool EnumWindowsProc(System.IntPtr hWnd, System.IntPtr lParam);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, System.IntPtr lParam);
'@
}

function Find-WinWSWindow {
    param([string]$TitleSubstring)

    $matches = [System.Collections.Generic.List[hashtable]]::new()
    $callback = [WinWS.ScreenshotInterop+EnumWindowsProc]{
        param([IntPtr]$hWnd, [IntPtr]$lParam)
        if (-not [WinWS.ScreenshotInterop]::IsWindowVisible($hWnd)) { return $true }
        $sb = [System.Text.StringBuilder]::new(512)
        $null = [WinWS.ScreenshotInterop]::GetWindowText($hWnd, $sb, $sb.Capacity)
        $title = $sb.ToString()
        if ($title -and $title.IndexOf($TitleSubstring, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $matches.Add(@{ Handle = $hWnd; Title = $title })
        }
        return $true
    }
    $null = [WinWS.ScreenshotInterop]::EnumWindows($callback, [IntPtr]::Zero)
    return $matches
}

function Get-WindowVisualBounds {
    param([IntPtr]$Handle)
    # DWMWA_EXTENDED_FRAME_BOUNDS = 9. Returns the real visible frame
    # (excludes the invisible Aero drop-shadow margin GetWindowRect reports).
    $rect = [WinWS.ScreenshotInterop+RECT]::new()
    $size = [System.Runtime.InteropServices.Marshal]::SizeOf([Type][WinWS.ScreenshotInterop+RECT])
    $hr = [WinWS.ScreenshotInterop]::DwmGetWindowAttribute($Handle, 9, [ref]$rect, $size)
    if ($hr -ne 0) {
        # DWM call failed (maybe DWM disabled). Fall back to GetWindowRect.
        $null = [WinWS.ScreenshotInterop]::GetWindowRect($Handle, [ref]$rect)
    }
    return [pscustomobject]@{
        X      = [int]$rect.Left
        Y      = [int]$rect.Top
        Width  = [int]($rect.Right  - $rect.Left)
        Height = [int]($rect.Bottom - $rect.Top)
    }
}

function Get-WindowTitle {
    param([IntPtr]$Handle)
    $sb = [System.Text.StringBuilder]::new(512)
    $null = [WinWS.ScreenshotInterop]::GetWindowText($Handle, $sb, $sb.Capacity)
    return $sb.ToString()
}

function Resolve-RepoRoot {
    $here = Split-Path -Parent $PSCommandPath
    return Split-Path -Parent $here
}

$repoRoot = Resolve-RepoRoot
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot 'output\screenshots'
}
$null = New-Item -ItemType Directory -Path $OutputDir -Force

$targetHandle = [IntPtr]::Zero
$targetTitle  = ''
if ($Hwnd -ne 0) {
    $targetHandle = [IntPtr]$Hwnd
    if (-not [WinWS.ScreenshotInterop]::IsWindow($targetHandle)) {
        Write-Error "Window handle 0x$('{0:X}' -f $Hwnd) is not valid."
        exit 1
    }
    $targetTitle = Get-WindowTitle -Handle $targetHandle
} else {
    $matchList = @(Find-WinWSWindow -TitleSubstring $WindowTitle)
    if ($matchList.Count -eq 0) {
        Write-Error "No visible window matched '$WindowTitle'. Open WinMint-UI.ps1 first."
        exit 1
    }
    if ($matchList.Count -gt 1) {
        Write-Warning "Multiple windows matched '$WindowTitle' — using the first:"
        foreach ($m in $matchList) { Write-Warning "  - 0x$('{0:X}' -f ([IntPtr]$m['Handle']).ToInt64()): $($m['Title'])" }
    }
    # Index into List[hashtable] explicitly. PS sometimes auto-unwraps generic Lists
    # in pipeline coercions; using $matchList[0]['Handle'] sidesteps that.
    $targetHandle = [IntPtr]$matchList[0]['Handle']
    $targetTitle  = [string]$matchList[0]['Title']
}

if ([WinWS.ScreenshotInterop]::IsIconic($targetHandle)) {
    # Restore minimized windows without activating them. WPF often renders blank
    # through PrintWindow while minimized, but the capture must not steal focus.
    $null = [WinWS.ScreenshotInterop]::ShowWindow($targetHandle, 4) # SW_SHOWNOACTIVATE
    Start-Sleep -Milliseconds 250
}

$bounds = Get-WindowVisualBounds -Handle $targetHandle
if ($bounds.Width -le 0 -or $bounds.Height -le 0) {
    Write-Error "Window bounds are invalid (W=$($bounds.Width) H=$($bounds.Height))."
    exit 1
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$label = if ($Page) {
    # Allow either a bare integer ("1" → "page1") or any string passed through.
    if ($Page -match '^\d+$') { "page$Page" } else { ($Page -replace '[^\w\-]', '_') }
} else {
    "winws-$timestamp"
}
$file = Join-Path $OutputDir ("{0}-{1}.png" -f $label, $timestamp)

$bmp = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
try {
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $hdc = $g.GetHdc()
        try {
            # PW_RENDERFULLCONTENT = 0x00000002. This asks DWM/user32 to render
            # the target window itself, so screenshots do not depend on focus or
            # whatever happens to be covering the app on the desktop.
            $printed = [WinWS.ScreenshotInterop]::PrintWindow($targetHandle, $hdc, 0x00000002)
        } finally {
            $g.ReleaseHdc($hdc)
        }
        if (-not $printed) {
            throw "PrintWindow failed for '$targetTitle' (0x$('{0:X}' -f $targetHandle.ToInt64()))."
        }
    } finally {
        $g.Dispose()
    }
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $bmp.Dispose()
}

[pscustomobject]@{
    File   = $file
    Width  = $bounds.Width
    Height = $bounds.Height
    Title  = $targetTitle
    Hwnd   = $targetHandle.ToInt64()
} | Format-List

Write-Host "Saved: $file"
