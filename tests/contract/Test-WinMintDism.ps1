#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'servicing\Invoke-WinMintDism.ps1')

$work = Join-Path ([IO.Path]::GetTempPath()) ('winmint-dism-contract-' + [Guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$env:WINMINT_SERVICING_WORK = $work

$stub = Join-Path $work 'fake-dism.ps1'
@'
Write-Output '[=====     50.0%                          ]'
Write-Output 'The operation completed successfully.'
exit 0
'@ | Set-Content -LiteralPath $stub -Encoding utf8

$barLine = '[=====     50.0%                          ]'
$okLine = 'The operation completed successfully.'
if (Test-WinMintDismProgressBarLine -Line '') { throw 'empty Line must be non-match (not throw)' }

$pipeline = @(
    Invoke-WinMintDism -DismPath (Get-Process -Id $PID).Path `
        -ArgumentList @('-NoProfile', '-File', $stub) `
        -Stage 'contract-probe'
)
if ($pipeline.Count -ne 0) { throw "default path must not emit success-stream lines (got $($pipeline.Count))" }
foreach ($line in $pipeline) {
    if (Test-WinMintDismProgressBarLine -Line $line) { throw 'default path surfaced DISM bar on pipeline' }
}

$transcript = Get-Content -LiteralPath (Join-Path $work 'dism-transcript.log') -Raw -Encoding utf8
if ($transcript -notmatch 'stage=contract-probe') { throw 'transcript missing stage banner' }
if ($transcript -notmatch [regex]::Escape($barLine)) { throw 'transcript missing progress bar line' }
if ($transcript -notmatch [regex]::Escape($okLine)) { throw 'transcript missing ok line' }

$text = Invoke-WinMintDism -DismPath (Get-Process -Id $PID).Path `
    -ArgumentList @('-NoProfile', '-File', $stub) `
    -Stage 'contract-passthru' `
    -PassThruText
if ($text -notmatch [regex]::Escape($barLine)) { throw 'PassThruText missing bar' }
if ($text -notmatch [regex]::Escape($okLine)) { throw 'PassThruText missing ok line' }

$savedWork = $env:WINMINT_SERVICING_WORK
$env:WINMINT_SERVICING_WORK = ''
$threw = $false
try {
    $null = Invoke-WinMintDism -ArgumentList @('/?') -Stage 'missing-env'
}
catch {
    $threw = $true
    if ($_.Exception.Message -notmatch 'WINMINT_SERVICING_WORK') { throw "missing-env message: $($_.Exception.Message)" }
}
finally {
    $env:WINMINT_SERVICING_WORK = $savedWork
}
if (-not $threw) { throw 'missing WINMINT_SERVICING_WORK must throw' }

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

Write-Output 'Test-WinMintDism ok'
exit 0
