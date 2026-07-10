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
        $logPath = Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log'
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

function Start-WinMintProvisioningHost {
    param(
        [int]$PollIntervalMs = 1500,
        [string]$HostExePath = '',
        [int]$MinStartDwellMs = 0,
        [int]$MinCompleteDwellMs = 0
    )

    $paths = Get-WinMintSetupShellLocalPaths
    $shellRoot = Get-WinMintSetupShellRoot
    $exePath = if (-not [string]::IsNullOrWhiteSpace($HostExePath)) { $HostExePath } else { Resolve-WinMintProvisioningHostExePath -ShellRoot $shellRoot }
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        throw "Provisioning host executable is missing: $exePath"
    }

    Stop-WinMintSetupShellHostProcesses
    Start-Sleep -Milliseconds 750

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
