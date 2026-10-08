#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$kernel = Get-Content -LiteralPath (Join-Path $repo 'servicing\Erase-OfflineOneDrive.ps1') -Raw
if ($kernel -notmatch 'Clear-WinMintOfflineOneDriveRun') {
    throw 'Erase-OfflineOneDrive must clear OneDrive Run values'
}
if ($kernel -notmatch 'OneDriveSetup\.exe') {
    throw 'Erase-OfflineOneDrive must delete OneDriveSetup.exe'
}
if ($kernel -notmatch 'takeown\.exe') {
    throw 'Erase-OfflineOneDrive must takeown TrustedInstaller-owned Setup'
}
if ($kernel -notmatch 'Users\\Default\\NTUSER\.DAT') {
    throw 'Erase-OfflineOneDrive must clear Default user Run hooks'
}
if ($kernel -notmatch '\$MountDir') {
    throw 'Erase-OfflineOneDrive must take MountDir'
}
if ($kernel -match '\$WorkDirectory|\$PoliciesPath|\$DefaultUserPath') {
    throw 'Erase-OfflineOneDrive must take MountDir only'
}
if ($kernel -match 'Registry::LocalMachine\.OpenSubKey|\[Microsoft\.Win32\.Registry\]::LocalMachine\.OpenSubKey') {
    throw 'Erase-OfflineOneDrive must clear Run via reg.exe (not .NET OpenSubKey on offline hive)'
}
if ($kernel -notmatch 'reg\.exe query' -or $kernel -notmatch 'reg\.exe delete') {
    throw 'Erase-OfflineOneDrive must use reg.exe query/delete for Run clears'
}

$plan = Get-Content -LiteralPath (Join-Path $repo 'servicing\Invoke-ServicingPlan.ps1') -Raw
if ($plan -notmatch "'EraseOfflineOneDrive'") {
    throw 'Invoke-ServicingPlan must resolve EraseOfflineOneDrive'
}

$stage = Get-Content -LiteralPath (Join-Path $repo 'servicing\Stage-Payload.ps1') -Raw
if ($stage -match 'OneDriveSetup\.exe') {
    throw 'Stage-Payload must not delete OneDriveSetup (EraseOfflineOneDrive owns that)'
}

Write-Output 'Test-EraseOfflineOneDrive ok'
exit 0
