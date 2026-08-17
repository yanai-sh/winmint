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
        $OutputIso = $null
    )
    try {
        $dir = Split-Path -Parent $Path
        if ($dir) { New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null }
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
        }
        ($doc | ConvertTo-Json -Compress) | Set-Content -LiteralPath $Path -Encoding utf8 -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not write Smoke status: $($_.Exception.Message)"
    }
}
