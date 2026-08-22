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
if ($smoke -notmatch 'Get-SmokePreferDiskBootDecision') { throw 'Invoke-Smoke must use Get-SmokePreferDiskBootDecision' }
if ($smoke -notmatch 'Get-SmokeEjectDvdDecision') { throw 'Invoke-Smoke must use Get-SmokeEjectDvdDecision' }
if ($smoke -notmatch "Running' \{[^}]*Prefer-DiskBoot") {
    throw 'Prefer-DiskBoot must run while VM is Running (before wpeutil reboot), not only on Stopping'
}
$preferFn = [regex]::Match(
    $smoke,
    '(?s)function Prefer-DiskBoot \{.*?function Dismount-InstallDvdWhenWindowsBoots').Value
if ([string]::IsNullOrWhiteSpace($preferFn)) { throw 'could not slice Prefer-DiskBoot' }
if ($preferFn -match 'Set-VMDvdDrive') {
    throw 'Prefer-DiskBoot must not eject the DVD (Set-VMDvdDrive) — 0xc0000178 STATUS_NO_MEDIA'
}

function Assert-Eq($Actual, $Expected, [string] $Message) {
    if ($Actual -cne $Expected) { throw "$Message (got '$Actual', expected '$Expected')" }
}

if ((Get-SmokeVmStartupBytes) -ne 8GB) { throw 'Smoke VM startup RAM must be 8GB (4GB is only the Win11 floor)' }

Assert-Eq (Get-SmokePreferDiskBootDecision -AlreadyPreferred $true -VhdHasImage $true) skip 'already preferred'
Assert-Eq (Get-SmokePreferDiskBootDecision -AlreadyPreferred $false -VhdHasImage $false) keep-dvd 'empty VHD keeps DVD'
Assert-Eq (Get-SmokePreferDiskBootDecision -AlreadyPreferred $false -VhdHasImage $true) prefer-hdd 'applied image prefers HDD'

Assert-Eq (Get-SmokeEjectDvdDecision -AlreadyEjected $false -DiskBootPreferred $false -HeartbeatOk $true) skip 'no prefer yet'
Assert-Eq (Get-SmokeEjectDvdDecision -AlreadyEjected $false -DiskBootPreferred $true -HeartbeatOk $false) skip 'WinPE heartbeat is not Windows'
Assert-Eq (Get-SmokeEjectDvdDecision -AlreadyEjected $false -DiskBootPreferred $true -HeartbeatOk $true) eject 'Windows heartbeat ejects DVD'
Assert-Eq (Get-SmokeEjectDvdDecision -AlreadyEjected $true -DiskBootPreferred $true -HeartbeatOk $true) skip 'already ejected'

$preferSrc = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/SmokeStatus.ps1') -Raw -Encoding utf8
if ($preferSrc -notmatch 'STATUS_NO_MEDIA') {
    throw 'harness must document 0xc0000178 STATUS_NO_MEDIA'
}

Write-Output 'Test-SmokeDiskBoot ok'
exit 0
