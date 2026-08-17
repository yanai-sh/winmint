#requires -Version 7.6
# Prefer-DiskBoot must not eject the install ISO. Ejecting on VM Stopping races WinPE
# wpeutil reboot and surfaces Boot Manager 0xc0000178 STATUS_NO_MEDIA.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$smoke = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Invoke-Smoke.ps1') -Raw -Encoding utf8

if ($smoke -notmatch '(?s)function Prefer-DiskBoot \{.*?function ') {
    throw 'Prefer-DiskBoot function not found'
}
$prefer = [regex]::Match($smoke, '(?s)function Prefer-DiskBoot \{.*?^function ', [System.Text.RegularExpressions.RegexOptions]::Multiline).Value
if ([string]::IsNullOrWhiteSpace($prefer)) { throw 'could not slice Prefer-DiskBoot' }
if ($prefer -match 'Set-VMDvdDrive') {
    throw 'Prefer-DiskBoot must not eject the DVD (Set-VMDvdDrive) — 0xc0000178 STATUS_NO_MEDIA'
}
if ($smoke -notmatch 'function Dismount-InstallDvdWhenWindowsBoots') {
    throw 'Dismount-InstallDvdWhenWindowsBoots missing'
}
if ($smoke -notmatch 'Test-GuestWindowsHeartbeat') {
    throw 'DVD eject must wait for Windows heartbeat'
}
if ($smoke -notmatch 'STATUS_NO_MEDIA') {
    throw 'harness must document 0xc0000178 STATUS_NO_MEDIA'
}
if ($smoke -notmatch "Running' \{[^}]*Prefer-DiskBoot") {
    throw 'Prefer-DiskBoot must run while VM is Running (before wpeutil reboot), not only on Stopping'
}

Write-Output 'Test-SmokeDiskBoot ok'
exit 0
