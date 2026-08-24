#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools\host\CheckStatus.ps1')

if ((Get-CheckWatchVerdict -Phase format) -cne 'continue') { throw 'running phase is continue' }
if ((Get-CheckWatchVerdict -Phase contract) -cne 'continue') { throw 'contract is continue' }
if ((Get-CheckWatchVerdict -Phase passed) -cne 'done') { throw 'passed is done' }
if ((Get-CheckWatchVerdict -Phase failed) -cne 'done') { throw 'failed is done' }
if ((Get-CheckWatchVerdict -Phase '') -cne 'continue') { throw 'empty is continue' }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('check-status-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $path = Join-Path $tmp 'check-status.json'
    Write-CheckStatus -Path $path -RunId 'run1' -Phase format -LastHostLine 'dotnet format'
    $doc = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
    if ($doc.schemaVersion -cne 'winmint.check.status/v1') { throw 'schemaVersion' }
    if ($doc.runId -cne 'run1') { throw 'runId' }
    if ($doc.phase -cne 'format') { throw 'phase' }
    if ($doc.leaf -cne '') { throw 'leaf empty outside contract' }
    if ($doc.PSObject.Properties.Name -contains 'index') { throw 'index must be omitted outside contract' }

    Write-CheckStatus -Path $path -RunId 'run1' -Phase contract -Leaf 'Test-Foo.ps1' `
        -LastHostLine 'Test-Foo.ps1' -Index 4 -Count 28
    $doc = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
    if ($doc.phase -cne 'contract') { throw 'contract phase' }
    if ($doc.leaf -cne 'Test-Foo.ps1') { throw 'leaf' }
    if ([int]$doc.index -ne 4) { throw 'index' }
    if ([int]$doc.count -ne 28) { throw 'count' }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$gate = Get-Content -LiteralPath (Join-Path $repo 'tools\host\Invoke-CheckGate.ps1') -Raw -Encoding utf8
if ($gate -match 'Get-Content[^\n]*check-status\.json') {
    throw 'check-gate must not read check-status.json as control plane'
}
if ($gate -notmatch 'Write-CheckStatus') { throw 'check-gate must write Check status' }
if ($gate -notmatch '-StatusPath') { throw 'check-gate must pass -StatusPath to contract tests' }
foreach ($phase in @('format', 'restore', 'build', 'test', 'analyzer', 'contract', 'passed', 'failed')) {
    if ($gate -notmatch $phase) { throw "check-gate missing phase $phase" }
}

$runner = Get-Content -LiteralPath (Join-Path $repo 'tests\contract\Invoke-ContractTests.ps1') -Raw -Encoding utf8
if ($runner -notmatch 'Write-CheckStatus') { throw 'contract runner must write Check status leaf' }
if ($runner -notmatch '-Phase contract') { throw 'contract runner must set phase contract' }

$watch = Get-Content -LiteralPath (Join-Path $repo 'tools\host\Watch-Host.ps1') -Raw -Encoding utf8
if ($watch -notmatch 'Get-CheckWatchVerdict') { throw 'Watch-Host check must call Get-CheckWatchVerdict' }
if ($watch -notmatch 'Format-WinMintHostWatch') { throw 'Watch-Host must render via Format-WinMintHostWatch' }
if ($watch -match 'Get-Date') { throw 'Watch-Host must not use Get-Date as a dashboard clock' }
if ($watch -notmatch 'doneTicks') { throw 'Watch-Host must tick done' }
if ($watch -notmatch '-ge 3') { throw 'Watch-Host must exit after three done ticks' }

$just = Get-Content -LiteralPath (Join-Path $repo 'Justfile') -Raw -Encoding utf8
if ($just -notmatch 'watch-check') { throw 'Justfile must expose watch-check' }
$checkRecipe = [regex]::Match($just, '(?m)^check:\r?\n(?:[ \t].*\r?\n)*')
if ($checkRecipe.Value -match 'Watch-Host') {
    throw 'just check must not auto-spawn Watch-Host'
}

Write-Output 'Test-CheckStatus ok'
