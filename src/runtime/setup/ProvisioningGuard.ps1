#Requires -Version 7.6

function Resolve-WinMintProvisioningHostExePath {
    param([string]$ShellRoot = '')

    if ([string]::IsNullOrWhiteSpace($ShellRoot)) {
        $ShellRoot = Get-WinMintSetupShellRoot
    }

    $exe = Join-Path $ShellRoot 'WinMintSetupShell.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        throw "Provisioning host executable is missing under $ShellRoot"
    }
    return $exe
}

function Write-WinMintProvisioningGuardLog {
    param([Parameter(Mandatory)][string]$Marker)

    try {
        $logDir = 'C:\ProgramData\WinMint\Logs'
        if (Get-Command Get-WinMintFirstLogonContext -ErrorAction SilentlyContinue) {
            try {
                $ctxLog = [string](Get-WinMintFirstLogonContext).LogDir
                if (-not [string]::IsNullOrWhiteSpace($ctxLog)) { $logDir = $ctxLog }
            }
            catch { }
        }
        if (-not (Test-Path -LiteralPath $logDir)) {
            $null = New-Item -ItemType Directory -Path $logDir -Force
        }
        $logPath = Join-Path $logDir 'FirstLogon.log'
        "$(Get-Date -Format 'o') provisioning-lock:$Marker" | Out-File -LiteralPath $logPath -Append
    }
    catch { }
}

function Enable-WinMintProvisioningGuard {
    param(
        # Preview/dev harness only — production engage must leave this off so Alt+Tab is blocked.
        [switch]$AllowTaskSwitch
    )

    try {
        & reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' /v NoWinKeys /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    }
    catch { }
    if (-not $AllowTaskSwitch) {
        try {
            & reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System' /v DisableTaskSwitching /t REG_DWORD /d 1 /f 2>&1 | Out-Null
        }
        catch { }
    }
    Write-WinMintProvisioningGuardLog -Marker 'guard-engage'
}

function Disable-WinMintProvisioningGuard {
    try {
        & reg.exe delete 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' /v NoWinKeys /f 2>&1 | Out-Null
    }
    catch { }
    try {
        & reg.exe delete 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System' /v DisableTaskSwitching /f 2>&1 | Out-Null
    }
    catch { }
    Write-WinMintProvisioningGuardLog -Marker 'guard-release'
}

function Invoke-WinMintProvisioningDismissStartMenu {
    if (-not ('WinMint.StartDismiss' -as [type])) {
        $null = Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
namespace WinMint {
    public static class StartDismiss {
        [DllImport("user32.dll")]
        static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, uint dwExtraInfo);
        const byte VK_ESCAPE = 0x1B;
        const uint KEYUP = 0x0002;
        public static void Dismiss() {
            keybd_event(VK_ESCAPE, 0, 0, 0);
            keybd_event(VK_ESCAPE, 0, KEYUP, 0);
        }
    }
}
'@
    }
    [WinMint.StartDismiss]::Dismiss()
}

function Restore-WinMintProvisioningDesktop {
    if (-not ('WinMint.DesktopRestore' -as [type])) {
        $null = Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace WinMint {
    public static class DesktopRestore {
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern IntPtr FindWindow(string className, string windowName);
        [DllImport("user32.dll")]
        static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        public static void ShowTaskbars() {
            foreach (var cls in new[] { "Shell_TrayWnd", "Shell_SecondaryTrayWnd" }) {
                var h = FindWindow(cls, null);
                if (h != IntPtr.Zero) {
                    ShowWindow(h, 5);
                }
            }
        }
    }
}
'@
    }
    [WinMint.DesktopRestore]::ShowTaskbars()
    Invoke-WinMintProvisioningDismissStartMenu
}

function Stop-WinMintSetupShellHostProcesses {
    Get-Process -Name 'WinMintSetupShell' -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_ | Stop-Process -Force -ErrorAction SilentlyContinue } catch { }
    }
}

function Stop-WinMintProvisioningHostResidual {
    Disable-WinMintProvisioningGuard
    Stop-WinMintSetupShellHostProcesses
    Restore-WinMintProvisioningDesktop
}

function Get-WinMintProvisioningHostProcess {
    return @(Get-Process -Name 'WinMintSetupShell' -ErrorAction SilentlyContinue | Sort-Object StartTime -Descending)[0]
}

function Write-WinMintProvisioningHostBootstrapFiles {
    param(
        [Parameter(Mandatory)][string]$ShellRoot,
        [Parameter(Mandatory)][string]$ControlPath,
        [Parameter(Mandatory)][string]$StatusPath,
        [string]$ProfileName = 'WinMint',
        [string]$TaskLabel = 'Starting WinMint setup…'
    )

    $startedAt = Get-Date -Format o
    $control = [ordered]@{
        phase = 'running'
        startedAt = $startedAt
        updatedAt = $startedAt
        profileName = $ProfileName
        message = ''
        preAgentStage = 'locked'
    }
    $status = [ordered]@{
        phase = 'running'
        stageId = 'ready'
        taskLabel = 'Getting things ready'
        detailLabel = if ($TaskLabel -and $TaskLabel -ne 'Starting WinMint setup…') { $TaskLabel } else { 'This may take a few minutes' }
        itemIndex = 0
        itemTotal = 0
        progressPct = 0
        progressMode = 'indeterminate'
        profileName = $ProfileName
        elapsedMs = 0
        groupLabel = ''
        banner = ''
        bannerKind = ''
        logDir = 'C:\ProgramData\WinMint\Logs'
        updatedAt = $startedAt
    }

    foreach ($path in @($ControlPath, $StatusPath)) {
        $dir = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $dir)) {
            $null = New-Item -ItemType Directory -Path $dir -Force
        }
    }
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($ControlPath, ($control | ConvertTo-Json -Depth 8), $utf8)
    [System.IO.File]::WriteAllText($StatusPath, ($status | ConvertTo-Json -Depth 8), $utf8)
    $mirror = Join-Path $ShellRoot 'setup-shell-status.json'
    try { [System.IO.File]::WriteAllText($mirror, ($status | ConvertTo-Json -Depth 8), $utf8) } catch { }
}

function Start-WinMintProvisioningHostEarly {
    <#
    .SYNOPSIS
        PreLock entry: cover the desktop before FirstLogon.ps1 loads modules.
    #>
    param(
        [string]$PayloadRoot = $PSScriptRoot,
        [int]$PollIntervalMs = 1500
    )

    $existing = Get-WinMintProvisioningHostProcess
    if ($existing) {
        Write-WinMintProvisioningGuardLog -Marker "host-adopt presenter=native pid=$($existing.Id) early=1"
        return $existing
    }

    $shellRoot = Join-Path $PayloadRoot 'setup-shell'
    $exePath = Join-Path $shellRoot 'WinMintSetupShell.exe'
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        Write-WinMintProvisioningGuardLog -Marker "host-early-skip missing=$exePath"
        return $null
    }

    $winMintDir = Join-Path $env:LOCALAPPDATA 'WinMint'
    $controlPath = Join-Path $winMintDir 'setup-shell-control.json'
    $statusPath = Join-Path $winMintDir 'setup-shell-status.json'
    $profileName = 'WinMint'
    try {
        $setupProfile = Join-Path $PayloadRoot 'WinMintSetupProfile.json'
        if (Test-Path -LiteralPath $setupProfile) {
            $sp = Get-Content -LiteralPath $setupProfile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($sp.PSObject.Properties['profileName'] -and $sp.profileName) {
                $profileName = [string]$sp.profileName
            }
        }
    }
    catch { }

    Write-WinMintProvisioningHostBootstrapFiles `
        -ShellRoot $shellRoot `
        -ControlPath $controlPath `
        -StatusPath $statusPath `
        -ProfileName $profileName `
        -TaskLabel 'Lock desktop and open setup shell'

    $minStartDwellMs = 5000
    $minCompleteDwellMs = 5000
    if (Get-Command Get-WinMintSetupProvisioningShellDwellOverrideMs -ErrorAction SilentlyContinue) {
        $dwellOverride = Get-WinMintSetupProvisioningShellDwellOverrideMs
        if ($dwellOverride) {
            $minStartDwellMs = $dwellOverride
            $minCompleteDwellMs = $dwellOverride
        }
    }

    $hostArgs = @(
        '--shell-root', "`"$shellRoot`"",
        '--status', "`"$statusPath`"",
        '--control', "`"$controlPath`"",
        '--poll-ms', $PollIntervalMs,
        '--min-start-dwell-ms', $minStartDwellMs,
        '--min-complete-dwell-ms', $minCompleteDwellMs,
        '--log'
    )
    $proc = Start-Process -FilePath $exePath -ArgumentList $hostArgs -PassThru
    Write-WinMintProvisioningGuardLog -Marker "host-start presenter=native pid=$($proc.Id) early=1"
    return $proc
}

function Start-WinMintProvisioningHost {
    param(
        [int]$PollIntervalMs = 1500,
        [string]$HostExePath = '',
        [int]$MinStartDwellMs = 0,
        [int]$MinCompleteDwellMs = 0,
        [switch]$AdoptIfRunning
    )

    if ($AdoptIfRunning) {
        $existing = Get-WinMintProvisioningHostProcess
        if ($existing) {
            Write-WinMintProvisioningGuardLog -Marker "host-adopt presenter=native pid=$($existing.Id)"
            return $existing
        }
    }

    $paths = Get-WinMintSetupShellLocalPaths
    $shellRoot = Get-WinMintSetupShellRoot
    $exePath = if (-not [string]::IsNullOrWhiteSpace($HostExePath)) { $HostExePath } else { Resolve-WinMintProvisioningHostExePath -ShellRoot $shellRoot }
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        throw "Provisioning host executable is missing: $exePath"
    }

    Stop-WinMintSetupShellHostProcesses
    # Brief yield only when replacing a prior host; PreLock early start skips this path.
    Start-Sleep -Milliseconds 200

    if ($MinStartDwellMs -le 0) { $MinStartDwellMs = 5000 }
    if ($MinCompleteDwellMs -le 0) { $MinCompleteDwellMs = 5000 }
    if ($MinStartDwellMs -eq 5000) {
        $dwellOverride = Get-WinMintSetupProvisioningShellDwellOverrideMs
        if ($dwellOverride) {
            $MinStartDwellMs = $dwellOverride
            $MinCompleteDwellMs = $dwellOverride
        }
    }

    $hostArgs = @(
        '--shell-root', "`"$shellRoot`"",
        '--status', "`"$($paths.StatusPath)`"",
        '--control', "`"$($paths.ControlPath)`"",
        '--poll-ms', $PollIntervalMs,
        '--min-start-dwell-ms', $MinStartDwellMs,
        '--min-complete-dwell-ms', $MinCompleteDwellMs,
        '--log'
    )
    $proc = Start-Process -FilePath $exePath -ArgumentList $hostArgs -PassThru
    Write-WinMintProvisioningGuardLog -Marker "host-start presenter=native pid=$($proc.Id)"
    return $proc
}

function Wait-WinMintProvisioningHost {
    param(
        [Parameter(Mandatory)]$Process,
        [int]$TimeoutSeconds = 120
    )

    if (-not $Process) { return }
    $deadline = (Get-Date).AddSeconds([Math]::Max(5, $TimeoutSeconds))
    while ((Get-Date) -lt $deadline) {
        if ($Process.HasExited) {
            Stop-WinMintSetupShellStatusPump
            Stop-WinMintProvisioningHostResidual
            Write-WinMintProvisioningGuardLog -Marker 'host-exit'
            return
        }
        Invoke-WinMintSetupShellStatusPumpTick
        Start-Sleep -Milliseconds 250
    }
    try {
        if (-not $Process.HasExited) { $Process | Stop-Process -Force -ErrorAction SilentlyContinue }
    }
    catch { }
    Stop-WinMintSetupShellStatusPump
    Stop-WinMintProvisioningHostResidual
    Write-WinMintProvisioningGuardLog -Marker 'host-timeout'
}

function Stop-WinMintProvisioningHost {
    param([Parameter(Mandatory)]$Process)

    if (-not $Process -or $Process.HasExited) {
        Stop-WinMintSetupShellStatusPump
        Stop-WinMintProvisioningHostResidual
        return
    }
    try { $Process | Stop-Process -Force -ErrorAction SilentlyContinue } catch { }
    Stop-WinMintSetupShellStatusPump
    Stop-WinMintProvisioningHostResidual
}
