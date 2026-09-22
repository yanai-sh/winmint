#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$kernel = Get-Content -LiteralPath (Join-Path $repo 'servicing\Stamp-OfflinePolicies.ps1') -Raw
if ($kernel -match "-split ';'") { throw 'Stamp-OfflinePolicies still has a packed-string decoder' }
if ($kernel -notmatch 'ConvertFrom-Json') { throw 'Stamp-OfflinePolicies must read policies.json' }
if ($kernel -match 'Clear-WinMintOfflineOneDriveRun') { throw 'Stamp-OfflinePolicies must not clear OneDrive Run values' }
# Load key HKLM\WinMintPol_SOFTWARE ends with SOFTWARE: SetValue on Policies\Microsoft\Dsh
# is unauthorized (same as live HKLM\SOFTWARE). Sibling kernels use WinMintSoft / WinMintDU / WinMintAppx.
if ($kernel -match 'HKLM\\WinMintPol_\$hiveName') {
    throw 'Stamp-OfflinePolicies must not load the SOFTWARE hive under a key whose name ends with SOFTWARE'
}

Write-Output 'Test-PolicyPayloadJson ok'
exit 0
