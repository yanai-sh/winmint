#requires -Version 7.6
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'servicing/Write-WinMintApplyEvent.ps1')

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('winmint-apply-events-' + [guid]::NewGuid().ToString('N') + '.jsonl')
try {
    $env:WINMINT_SERVICING_RUN_ID = 'testrun'
    Write-WinMintApplyEvent -Path $tmp -Kind 'run.start' -Summary 'Apply start'
    Write-WinMintApplyEvent -Path $tmp -Kind 'opcode.end' -Opcode 'StampOfflineShell' -Index 1 -Count 2 `
        -Outcome ok -DurationMs 12 -Summary ('x' * 100)
    Write-WinMintApplyEvent -Path $tmp -Kind 'proof' -Opcode 'AddQualityUpdates' -Label 'quality-hash' `
        -Percent 25 -Summary 'quality hash 25%'
    Write-WinMintApplyEvent -Path $tmp -Kind 'run.end' -Outcome ok -Summary 'Apply ok'

    $lines = Get-Content -LiteralPath $tmp -Encoding utf8
    if ($lines.Count -ne 4) { throw "expected 4 events, got $($lines.Count)" }
    $op = $lines[1] | ConvertFrom-Json
    if ($op.kind -cne 'opcode.end') { throw 'opcode.end kind' }
    if ($op.summary.Length -gt 80) { throw 'summary must be <= 80' }
    if ($op.summary[-1] -cne [char]0x2026) { throw 'long summary must ellipsis' }
    $proof = $lines[2] | ConvertFrom-Json
    if ([double]$proof.percent -ne 25) { throw 'proof percent' }
}
finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

$plan = Get-Content -LiteralPath (Join-Path $repo 'servicing/Invoke-ServicingPlan.ps1') -Raw -Encoding utf8
if ($plan -notmatch 'Write-WinMintApplyEvent') { throw 'plan must emit apply events' }
if ($plan -notmatch 'apply-events\.jsonl') { throw 'plan must point log= at apply-events.jsonl' }

Write-Output 'Test-WinMintApplyEvent ok'
