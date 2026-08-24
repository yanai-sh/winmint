#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools\host\CheckStatus.ps1')

function Assert-Eq($Actual, $Expected, [string] $Message) {
    if ($Actual -cne $Expected) { throw "$Message (got '$Actual', expected '$Expected')" }
}

Assert-Eq (Get-CheckWatchVerdict -Phase format) continue 'running phase is continue'
Assert-Eq (Get-CheckWatchVerdict -Phase contract) continue 'contract is continue'
Assert-Eq (Get-CheckWatchVerdict -Phase passed) done 'passed is done'
Assert-Eq (Get-CheckWatchVerdict -Phase failed) done 'failed is done'
Assert-Eq (Get-CheckWatchVerdict -Phase '') continue 'empty is continue'

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('check-status-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $path = Join-Path $tmp 'check-status.json'
    Write-CheckStatus -Path $path -RunId 'run1' -Phase format -LastHostLine 'dotnet format'
    $doc = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-Eq $doc.schemaVersion 'winmint.check.status/v1' 'schemaVersion'
    Assert-Eq $doc.runId 'run1' 'runId'
    Assert-Eq $doc.phase 'format' 'phase'
    Assert-Eq $doc.leaf '' 'leaf empty outside contract'
    if ($doc.PSObject.Properties.Name -contains 'index') { throw 'index must be omitted outside contract' }

    Write-CheckStatus -Path $path -RunId 'run1' -Phase contract -Leaf 'Test-Foo.ps1' `
        -LastHostLine 'Test-Foo.ps1' -Index 4 -Count 28
    $doc = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-Eq $doc.phase 'contract' 'contract phase'
    Assert-Eq $doc.leaf 'Test-Foo.ps1' 'leaf'
    Assert-Eq ([int]$doc.index) 4 'index'
    Assert-Eq ([int]$doc.count) 28 'count'
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

$watch = Get-Content -LiteralPath (Join-Path $repo 'tools\host\Watch-CheckHost.ps1') -Raw -Encoding utf8
if ($watch -notmatch 'Get-CheckWatchVerdict') { throw 'Watch-CheckHost must call Get-CheckWatchVerdict' }
if ($watch -notmatch 'Format-WinMintHostWatch') { throw 'Watch-CheckHost must render via Format-WinMintHostWatch' }
if ($watch -match 'Get-Date') { throw 'Watch-CheckHost must not use Get-Date as a dashboard clock' }
if ($watch -notmatch 'doneTicks') { throw 'Watch-CheckHost must tick done' }
if ($watch -notmatch '-ge 3') { throw 'Watch-CheckHost must exit after three done ticks' }

$just = Get-Content -LiteralPath (Join-Path $repo 'Justfile') -Raw -Encoding utf8
if ($just -notmatch 'watch-check') { throw 'Justfile must expose watch-check' }
if ($just -match 'just check' -and $just -match 'Watch-CheckHost' ) {
    $checkRecipe = [regex]::Match($just, '(?m)^check:\r?\n.*')
    if ($checkRecipe.Value -match 'Watch-CheckHost') {
        throw 'just check must not auto-spawn Watch-CheckHost'
    }
}

Write-Output 'Test-CheckStatus ok'
