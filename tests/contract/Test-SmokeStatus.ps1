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
