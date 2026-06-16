# SetupComplete machine-phase module: install the WinMint toolchain packages that
# are not already bundled into the offline image.
# Dot-sourced by SetupComplete.ps1; relies on its script-scope $logDir and the
# helper functions Test-ScInternet443 / New-ScWingetInstallArgs.

function Invoke-ScToolchainInstall {
    if (-not (Test-ScInternet443)) {
        Write-ScLog 'Skipping winget toolchain (no outbound HTTPS to www.microsoft.com:443).'
        return
    }

    try {
        $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
        $env:PATH = "$machinePath;$userPath"
        $terminalArgs = New-ScWingetInstallArgs -Id 'Microsoft.WindowsTerminal'
        Start-Process -FilePath 'winget.exe' -ArgumentList $terminalArgs -Wait -NoNewWindow -ErrorAction SilentlyContinue
    }
    catch {
        "Toolchain install failed: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
    }
}
