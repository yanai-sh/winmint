#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$kernel = Get-Content -LiteralPath (Join-Path $repo 'servicing\Stamp-OfflinePolicies.ps1') -Raw
if ($kernel -match "-split ';'") { throw 'Stamp-OfflinePolicies still has a packed-string decoder' }
if ($kernel -notmatch 'ConvertFrom-Json') { throw 'Stamp-OfflinePolicies must read policies.json' }

Write-Output 'Test-PolicyPayloadJson ok'
exit 0
