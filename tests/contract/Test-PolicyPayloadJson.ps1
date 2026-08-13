#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$kernel = Get-Content -LiteralPath (Join-Path $repo 'servicing\Stamp-OfflinePolicies.ps1') -Raw
if ($kernel -match "-split ';'") { throw 'Stamp-OfflinePolicies still has a packed-string decoder' }
if ($kernel -notmatch 'ConvertFrom-Json') { throw 'Stamp-OfflinePolicies must read policies.json' }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('winmint-poljson-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $data = 'semi;pipe|tilde~~~~end'
    $path = Join-Path $tmp 'policies.json'
    @"
[{"hive":"SOFTWARE","subKey":"Policies\\WinMint\\Punctuation","name":"Example","regType":"REG_SZ","data":"$data","family":"edge","digest":"policy.edge.Example"}]
"@ | Set-Content -LiteralPath $path -Encoding utf8
    $rows = @(Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
    if ($rows.Count -ne 1) { throw "expected 1 row, got $($rows.Count)" }
    if ([string]$rows[0].data -ne $data) { throw "Data round-trip lost punctuation: $($rows[0].data)" }
    if ([string]$rows[0].digest -ne 'policy.edge.Example') { throw 'digest missing after JSON read' }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-PolicyPayloadJson ok'
exit 0
