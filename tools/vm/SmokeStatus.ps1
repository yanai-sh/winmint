#requires -Version 7.6
Set-StrictMode -Version Latest

function Resolve-SmokePhase {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('apply', 'wait', 'assert', 'green', 'failed')]
        [string] $HostStage,
        [string] $VmState,
        [long] $VhdFileSizeBytes = 0,
        [switch] $HeartbeatOk,
        [switch] $EvidenceReady
    )
    switch ($HostStage) {
        'apply' { return 'apply' }
        'assert' { return 'assert' }
        'green' { return 'green' }
        'failed' { return 'failed' }
    }
    if ($VmState -notin @('Running')) { return 'setup-reboot' }
    if ($HeartbeatOk) { return 'guest-up' }
    if ($VhdFileSizeBytes -ge 1GB) { return 'winpe-apply' }
    return 'vm-boot'
}

function Write-SmokeStatus {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Phase,
        [Parameter(Mandatory)][string] $VmName,
        $VmState = $null,
        $Cpu = $null,
        $Heartbeat = $null,
        $VhdFileSizeMB = $null,
        [int] $StallMinutesLeft = 0,
        [int] $WallMinutesLeft = 0,
        [string] $LastHostLine = '',
        $OutputIso = $null,
        [int] $WaiterPid = 0
    )
    try {
        $dir = Split-Path -Parent $Path
        if ($dir) { New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null }
        if ($WaiterPid -le 0) { $WaiterPid = [int]$PID }
        $doc = [ordered]@{
            schemaVersion    = 'winmint.smoke.status/v1'
            updatedAt        = [datetime]::UtcNow.ToString('o')
            phase            = $Phase
            vmName           = $VmName
            vmState          = $VmState
            cpu              = $Cpu
            heartbeat        = $Heartbeat
            vhdFileSizeMB    = $VhdFileSizeMB
            stallMinutesLeft = $StallMinutesLeft
            wallMinutesLeft  = $WallMinutesLeft
            lastHostLine     = $LastHostLine
            outputIso        = $OutputIso
            waiterPid        = $WaiterPid
        }
        ($doc | ConvertTo-Json -Compress) | Set-Content -LiteralPath $Path -Encoding utf8 -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not write Smoke status: $($_.Exception.Message)"
    }
}

function Start-SmokeMonitor {
    param(
        [Parameter(Mandatory)][string] $VmName,
        [string] $ConnectExe = (Join-Path $env:WINDIR 'System32\vmconnect.exe'),
        [scriptblock] $Launcher = {
            param($Exe, $Name)
            Start-Process -FilePath $Exe -ArgumentList @('localhost', $Name)
        }
    )
    if (-not (Test-Path -LiteralPath $ConnectExe)) {
        Write-Warning "vmconnect.exe not found; continuing headless"
        return
    }
    try {
        & $Launcher $ConnectExe $VmName
    }
    catch {
        Write-Warning "Could not start VMConnect: $($_.Exception.Message)"
    }
}

function Get-SmokeVmStartupBytes {
    # 8GB is apply/OOBE headroom; 4GB is only the Win11 floor.
    8GB
}

function Get-SmokePreferDiskBootDecision {
    param(
        [bool] $AlreadyPreferred,
        [bool] $VhdHasImage
    )
    if ($AlreadyPreferred) { return 'skip' }
    # ponytail: ejecting here races WinPE wpeutil reboot → Boot Manager 0xc0000178 STATUS_NO_MEDIA.
    if (-not $VhdHasImage) { return 'keep-dvd' }
    return 'prefer-hdd'
}

function Get-SmokeEjectDvdDecision {
    param(
        [bool] $AlreadyEjected,
        [bool] $DiskBootPreferred,
        [bool] $HeartbeatOk
    )
    if ($AlreadyEjected -or -not $DiskBootPreferred -or -not $HeartbeatOk) { return 'skip' }
    return 'eject'
}

function Get-SmokeWatchVerdict {
    <#
    .SYNOPSIS
      Watch-only verdict from Hyper-V-native signals + status freshness. Never infers death from PIDs.
    .NOTES
      Invoke-Smoke throws on empty-vhd. Watchers must not Stop-VM / Remove-VM;
      harness-stale stays watch-only.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Phase,
        [string] $VmState = '',
        [int] $VhdFileSizeMB = 0,
        [int] $StatusAgeSeconds = 0,
        [int] $EmptyVhdRunningSeconds = 0,
        [int] $EmptyVhdFailAfterSeconds = 480,
        [int] $HarnessStaleAfterSeconds = 120
    )
    if ($Phase -in @('green', 'failed', 'assert')) {
        return 'done'
    }
    # DISM Apply can run for hours without a status refresh.
    if ($Phase -eq 'apply') {
        return 'continue'
    }
    if ($VmState -eq 'Running' -and $VhdFileSizeMB -lt 1024 -and
        $EmptyVhdRunningSeconds -ge $EmptyVhdFailAfterSeconds) {
        return 'empty-vhd'
    }
    if ($StatusAgeSeconds -gt $HarnessStaleAfterSeconds) {
        return 'harness-stale'
    }
    return 'continue'
}
