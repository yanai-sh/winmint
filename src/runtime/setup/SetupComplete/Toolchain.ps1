# SetupComplete machine-phase module: install the WinMint toolchain packages that
# are not already bundled into the offline image.
# Dot-sourced by SetupComplete.ps1; relies on its script-scope $logDir and the
# helper functions Test-ScInternet443 / New-ScWingetInstallArgs.

function Resolve-ScWingetExePath {
    $cmd = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source -PathType Leaf)) {
        return [string]$cmd.Source
    }

    $pkg = Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue |
        Sort-Object { [version]($_.Version) } -Descending |
        Select-Object -First 1
    if ($pkg -and $pkg.InstallLocation) {
        $winget = Join-Path $pkg.InstallLocation 'winget.exe'
        if (Test-Path -LiteralPath $winget -PathType Leaf) { return $winget }
    }

    foreach ($candidate in @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'),
            (Join-Path $env:SystemRoot 'System32\winget.exe')
        )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }

    return $null
}

function Invoke-ScToolchainInstall {
    if (-not (Test-ScInternet443)) {
        Write-ScLog 'Skipping winget toolchain (no outbound HTTPS to www.microsoft.com:443).'
        return
    }

    $winget = Resolve-ScWingetExePath
    if (-not $winget) {
        Write-ScLog 'Skipping winget toolchain (winget.exe not found under SYSTEM/App Installer).'
        return
    }

    try {
        $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
        $env:PATH = "$machinePath;$userPath"
        $terminalArgs = New-ScWingetInstallArgs -Id 'Microsoft.WindowsTerminal'
        $p = Start-Process -FilePath $winget -ArgumentList $terminalArgs -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        Write-ScLog "winget Windows Terminal finished (exit=$([int]$p.ExitCode)) via $winget"
    }
    catch {
        "Toolchain install failed: $_" | Out-File (Join-Path $logDir 'SetupComplete_errors.log') -Append
    }
}
