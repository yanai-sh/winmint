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
if ($smoke -notmatch 'Set-VMMemory') {
    throw 'Set-VMMemory required (static 8GB; do not balloon during DISM apply)'
}
if ($smoke -notmatch 'StartupBytes 8GB') {
    throw 'Smoke VM startup RAM must be 8GB'
}
if ($smoke -match 'MemoryStartupBytes 4GB' -or $smoke -match 'StartupBytes 4GB') {
    throw '4GB is only the Win11 floor, not the smoke guest size'
}

# Hyper-V VMConnect click in the WinPE console is cmd Select Mode, not "press any key to boot".
$launch = Get-Content -LiteralPath (Join-Path $repo 'payload/winpe/LaunchApply.cmd') -Raw -Encoding ascii
if ($launch -notmatch 'reg add HKCU\\Console /v QuickEdit /t REG_DWORD /d 0 /f') {
    throw 'LaunchApply must disable console Quick Edit (Hyper-V click = select-mode pause)'
}
if ($launch -match '(?im)^\s*pause\b') {
    throw 'LaunchApply must not pause for a key'
}
if ($launch -match '(?im)^\s*set /p ') {
    throw 'LaunchApply must not wait on set /p'
}
if ($launch -match '(?im)^\s*choice\b') {
    throw 'LaunchApply must not wait on choice'
}
if ($launch -match 'Press any key') {
    throw 'LaunchApply must not prompt Press any key'
}
foreach ($line in ($launch -split '\r?\n')) {
    if ($line -match '(?i)^\s*timeout\b' -and $line -notmatch '/nobreak') {
        throw "LaunchApply timeout must use /nobreak: $line"
    }
}

Write-Output 'Test-SmokeDiskBoot ok'
exit 0
