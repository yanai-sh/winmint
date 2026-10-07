#requires -Version 7.6
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$start = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Start-SmokeElevated.ps1') -Raw -Encoding utf8
$elev = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Invoke-SmokeElevated.ps1') -Raw -Encoding utf8
$just = Get-Content -LiteralPath (Join-Path $repo 'Justfile') -Raw -Encoding utf8

if ($start -notmatch 'Resolve-WinMintWindowsTerminal') { throw 'Start-SmokeElevated must resolve wt' }
if ($start -notmatch 'ArgumentList\.Add') { throw 'Start-SmokeElevated must use ProcessStartInfo.ArgumentList' }
if ($start -notmatch "'-w',\s*'0'") { throw 'Start-SmokeElevated must open a new wt window (-w 0)' }
if ($start -notmatch 'sudo') { throw 'Start-SmokeElevated must elevate via sudo when not admin' }
if ($start -notmatch 'Invoke-SmokeElevated\.ps1') { throw 'Start-SmokeElevated must target Invoke-SmokeElevated' }
if ($start -notmatch 'WT_SESSION') { throw 'Start-SmokeElevated must detect an existing Windows Terminal session' }

if ($elev -match '& pwsh -NoProfile -File \$recipe') {
    throw 'Invoke-SmokeElevated must not nest pwsh.exe for the recipe (conhost)'
}
if ($elev -notmatch '& \$recipe') { throw 'Invoke-SmokeElevated must invoke recipe in-process' }
if ($elev -notmatch 'Start-SmokeElevated') { throw 'Invoke-SmokeElevated help must point at Start-SmokeElevated' }

if ($just -notmatch 'Start-SmokeElevated\.ps1') { throw 'just smoke-maintainer* must use Start-SmokeElevated' }

Write-Host 'Test-SmokeElevatedLaunch ok'
