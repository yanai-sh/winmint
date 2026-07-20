# SetupComplete machine-phase module: console host sanity check only.
# Dot-sourced by SetupComplete.ps1; relies on script-scope Write-ScLog.
#
# Windows 11 25H2+ (WinMint's supported source) already ships Windows Terminal.
# winget install/upgrade here was redundant and hung under SYSTEM (often while a
# Terminal/App Installer related process was already active). Offline settings are
# staged into the image; FirstLogon finalizes profiles and can fall back to pwsh.

function Test-ScWindowsTerminalPresent {
    foreach ($name in @('Microsoft.WindowsTerminal', 'Microsoft.WindowsTerminalPreview')) {
        if (Get-AppxPackage -AllUsers -Name $name -ErrorAction SilentlyContinue) {
            return $true
        }
    }
    foreach ($candidate in @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'),
            (Join-Path $env:ProgramFiles 'Windows Terminal\wt.exe')
        )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $true
        }
    }
    return $false
}

function Invoke-ScToolchainInstall {
    if (Test-ScWindowsTerminalPresent) {
        Write-ScLog 'Windows Terminal present (inbox); SetupComplete does not winget-install or upgrade it.'
        return
    }

    # Unexpected on supported media — do not winget during SetupComplete (hang risk).
    Write-ScWarn 'Windows Terminal missing from image; skipping SetupComplete winget (FirstLogon falls back to pwsh console).'
}
