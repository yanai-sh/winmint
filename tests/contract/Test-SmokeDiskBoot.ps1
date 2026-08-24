#requires -Version 7.6
# Disk-boot / DVD / RAM policy from native signals (Get-VHD FileSize, Heartbeat).
# Prefer-HDD must not eject — ejecting on VM Stopping races WinPE wpeutil reboot
# and surfaces Boot Manager 0xc0000178 STATUS_NO_MEDIA.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools/vm/SmokeStatus.ps1')

$smoke = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Invoke-Smoke.ps1') -Raw -Encoding utf8
if ($smoke -notmatch 'Get-SmokeVmStartupBytes') { throw 'Invoke-Smoke must use Get-SmokeVmStartupBytes' }
if ($smoke -notmatch 'Get-SmokeWaitTick') { throw 'Invoke-Smoke must use Get-SmokeWaitTick' }
$preferFn = [regex]::Match(
    $smoke,
    '(?s)function Prefer-DiskBoot \{.*?function Dismount-InstallDvdWhenWindowsBoots').Value
if ([string]::IsNullOrWhiteSpace($preferFn)) { throw 'could not slice Prefer-DiskBoot' }
if ($preferFn -match 'Set-VMDvdDrive') {
    throw 'Prefer-DiskBoot must not eject the DVD (Set-VMDvdDrive) — 0xc0000178 STATUS_NO_MEDIA'
}

if ((Get-SmokeVmStartupBytes) -ne 8GB) { throw 'Smoke VM startup RAM must be 8GB (4GB is only the Win11 floor)' }

function Invoke-Tick {
    param([hashtable] $Over = @{})
    $s = @{
        VmState                  = 'Running'
        LastVmState              = 'Running'
        Cpu                      = 0
        VhdFileSizeBytes         = 2GB
        VhdHasImage              = $true
        HeartbeatOk              = $false
        GuestUpSticky            = $false
        ConsecutiveHeartbeatOk   = 0
        DiskBootPreferred        = $false
        DvdEjected               = $false
        SmokeRunIdStamped        = $false
        LastFingerprint          = ''
        Fingerprint              = ''
        SupervisorRunning        = $false
        SetupRebootCount         = 0
        MaxSetupReboots          = 8
        StallElapsedMinutes      = 0
        StallMinutes             = 45
        EmptyVhdRunningSeconds   = 0
        EmptyVhdFailAfterSeconds = 480
        NudgeElapsedMinutes      = 0
        HalfStallShot            = $false
    }
    foreach ($k in $Over.Keys) { $s[$k] = $Over[$k] }
    Get-SmokeWaitTick -Snap ([pscustomobject]$s)
}

$t = Invoke-Tick @{ DiskBootPreferred = $true; VhdHasImage = $true }
if ($t.PreferDisk -cne 'skip') { throw 'already preferred' }
$t = Invoke-Tick @{ DiskBootPreferred = $false; VhdHasImage = $false; VhdFileSizeBytes = 100MB }
if ($t.PreferDisk -cne 'keep-dvd') { throw 'empty VHD keeps DVD' }
$t = Invoke-Tick @{ DiskBootPreferred = $false; VhdHasImage = $true; HeartbeatOk = $false }
if ($t.PreferDisk -cne 'prefer-hdd') { throw 'applied image prefers HDD' }
if ($t.EjectDvd -cne 'skip') { throw 'prefer-hdd without heartbeat must not eject' }
$t = Invoke-Tick @{ DiskBootPreferred = $false; VhdHasImage = $true; HeartbeatOk = $true }
if ($t.PreferDisk -cne 'prefer-hdd') { throw 'same-poll prefer-hdd' }
if ($t.EjectDvd -cne 'eject') { throw 'Windows heartbeat ejects DVD after prefer-hdd same poll' }
$t = Invoke-Tick @{ DiskBootPreferred = $true; HeartbeatOk = $false }
if ($t.EjectDvd -cne 'skip') { throw 'WinPE heartbeat is not Windows' }
$t = Invoke-Tick @{ DiskBootPreferred = $true; HeartbeatOk = $true; DvdEjected = $true }
if ($t.EjectDvd -cne 'skip') { throw 'already ejected' }
$t = Invoke-Tick @{ VmState = 'Stopping'; VhdHasImage = $true; DiskBootPreferred = $false }
if ($t.PreferDisk -cne 'prefer-hdd') { throw 'Stopping still prefers HDD' }
if ($t.EjectDvd -cne 'skip') { throw 'Stopping must not eject' }

$preferSrc = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/SmokeStatus.ps1') -Raw -Encoding utf8
if ($preferSrc -notmatch 'STATUS_NO_MEDIA') {
    throw 'harness must document 0xc0000178 STATUS_NO_MEDIA'
}

Write-Output 'Test-SmokeDiskBoot ok'
exit 0
