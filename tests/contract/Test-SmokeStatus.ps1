#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools/vm/SmokeStatus.ps1')

$smoke = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Invoke-Smoke.ps1') -Raw -Encoding utf8
if ($smoke -notmatch 'tools[/\\]vm[/\\]SmokeStatus\.ps1') { throw 'Invoke-Smoke must dot-source SmokeStatus.ps1' }
if ($smoke -notmatch '\[switch\]\s*\$Monitor') { throw '-Monitor switch missing' }
if ($smoke -notmatch 'Start-SmokeMonitor') { throw 'Start-SmokeMonitor not called' }
if ($smoke -notmatch 'Write-SmokeStatus') { throw 'Write-SmokeStatus not called' }
if ($smoke -match 'Get-Content[^\n]*smoke-status\.json') { throw 'must not read smoke-status.json as control plane' }
if ($smoke -notmatch 'Get-SmokeWatchVerdict') { throw 'Invoke-Smoke wait loop must call Get-SmokeWatchVerdict' }
if ($smoke -notmatch 'EMPTY_VHD:') { throw 'empty-VHD throw prefix missing (operator copy)' }
if ($smoke -notmatch '\[Diagnostics\.Stopwatch\]') { throw 'stall/wall/empty-vhd must use Stopwatch, not UtcNow deadlines' }
if ($smoke -notmatch 'Enable-VMEventing') { throw 'Enable-VMEventing keeps Hyper-V objects fresh without host polling' }
if ($smoke -match 'process-exited-early' -or $smoke -match 'Find-SmokePids') {
    throw 'Invoke-Smoke must not infer harness death from process lists'
}

function Assert-Eq($Actual, $Expected, [string] $Message) {
    if ($Actual -cne $Expected) { throw "$Message (got '$Actual', expected '$Expected')" }
}

Assert-Eq (Resolve-SmokePhase -HostStage apply) apply 'apply stage'
Assert-Eq (Resolve-SmokePhase -HostStage assert) assert 'assert stage'
Assert-Eq (Resolve-SmokePhase -HostStage green) green 'green stage'
Assert-Eq (Resolve-SmokePhase -HostStage failed) failed 'failed stage'
Assert-Eq (Resolve-SmokePhase -HostStage wait -VmState Stopping) setup-reboot 'setup reboot'
Assert-Eq (Resolve-SmokePhase -HostStage wait -VmState Off) setup-reboot 'setup off'
Assert-Eq (Resolve-SmokePhase -HostStage wait -VmState Starting) setup-reboot 'setup starting'
Assert-Eq (Resolve-SmokePhase -HostStage wait -VmState Running -VhdFileSizeBytes 100MB) vm-boot 'empty VHD'
Assert-Eq (Resolve-SmokePhase -HostStage wait -VmState Running -VhdFileSizeBytes 1GB) winpe-apply 'VHD has image'
Assert-Eq (Resolve-SmokePhase -HostStage wait -VmState Running -VhdFileSizeBytes 1GB -HeartbeatOk) guest-up 'heartbeat wins VHD'
Assert-Eq (Resolve-SmokePhase -HostStage wait -VmState Running -HeartbeatOk -EvidenceReady) guest-up 'evidence ready still guest-up until HostStage assert'

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('smoke-status-' + [guid]::NewGuid().ToString('N'))
$statusPath = Join-Path $tmp 'smoke-status.json'
try {
    Write-SmokeStatus -Path $statusPath -Phase apply -VmName 'winmint-smoke' `
        -StallMinutesLeft 45 -WallMinutesLeft 180 -LastHostLine 'Applying'
    $doc = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
    Assert-Eq $doc.schemaVersion 'winmint.smoke.status/v1' 'schema'
    Assert-Eq $doc.phase 'apply' 'written phase'
    Assert-Eq $doc.vmName 'winmint-smoke' 'vm name'
    if ($null -eq $doc.updatedAt) { throw 'updatedAt missing' }
    if ([int]$doc.waiterPid -ne [int]$PID) { throw "waiterPid should default to this pwsh (got $($doc.waiterPid))" }

    $watchParams = (Get-Command Get-SmokeWatchVerdict).Parameters.Keys
    if ($watchParams -match 'Pid') { throw 'Get-SmokeWatchVerdict must not take a PID list' }

    Assert-Eq (Get-SmokeWatchVerdict -Phase green) done 'green is done'
    Assert-Eq (Get-SmokeWatchVerdict -Phase failed) done 'failed is done'
    Assert-Eq (Get-SmokeWatchVerdict -Phase assert) done 'assert is done'
    Assert-Eq (Get-SmokeWatchVerdict -Phase apply -StatusAgeSeconds 99999) continue 'apply may be silent for hours'
    Assert-Eq (Get-SmokeWatchVerdict -Phase apply -VmState Running -VhdFileSizeMB 36 -EmptyVhdRunningSeconds 480) continue 'apply is host DISM, not empty-VHD'
    Assert-Eq (Get-SmokeWatchVerdict -Phase guest-up -VmState Running -VhdFileSizeMB 17000 -StatusAgeSeconds 5) continue 'guest-up with fresh status is live (not missing PIDs)'
    Assert-Eq (Get-SmokeWatchVerdict -Phase winpe-apply -VmState Running -VhdFileSizeMB 2048 -StatusAgeSeconds 5) continue 'VHD growth is WinPE apply progress'
    Assert-Eq (Get-SmokeWatchVerdict -Phase setup-reboot -VmState Off -VhdFileSizeMB 36 -EmptyVhdRunningSeconds 480) continue 'Off is setup reboot, not empty-VHD'
    Assert-Eq (Get-SmokeWatchVerdict -Phase guest-up -StatusAgeSeconds 200) harness-stale 'stale status after wait phases'
    Assert-Eq (Get-SmokeWatchVerdict -Phase vm-boot -VmState Running -VhdFileSizeMB 36 -EmptyVhdRunningSeconds 60) continue 'empty VHD under budget'
    Assert-Eq (Get-SmokeWatchVerdict -Phase vm-boot -VmState Running -VhdFileSizeMB 36 -EmptyVhdRunningSeconds 480) empty-vhd 'empty VHD after Running budget'

    $blocked = Join-Path $tmp 'blocked'
    Set-Content -LiteralPath $blocked -Value 'not-a-dir' -Encoding utf8
    try {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        Write-SmokeStatus -Path (Join-Path $blocked 'smoke-status.json') -Phase failed `
            -VmName 'winmint-smoke' -StallMinutesLeft 0 -WallMinutesLeft 0 -LastHostLine 'fail'
    } finally {
        $ErrorActionPreference = $prevEap
    }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Start-SmokeMonitor -VmName 'winmint-smoke' -ConnectExe 'C:\no-such-vmconnect.exe'
$script:launched = $null
Start-SmokeMonitor -VmName 'winmint-smoke' -ConnectExe $PSCommandPath -Launcher {
    param($Exe, $VmName)
    $script:launched = @{ Exe = $Exe; VmName = $VmName }
}
if ($null -eq $script:launched) { throw 'Launcher not called for existing ConnectExe' }
Assert-Eq $script:launched.VmName 'winmint-smoke' 'vmconnect vm name'
Start-SmokeMonitor -VmName 'x' -ConnectExe $PSCommandPath -Launcher { throw 'boom' }

Write-Output 'Test-SmokeStatus ok'
exit 0
