#requires -Version 7.6
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$start = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Start-SmokeElevated.ps1') -Raw -Encoding utf8
$elev = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Invoke-SmokeElevated.ps1') -Raw -Encoding utf8
$recipe = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Invoke-SmokeRecipe.ps1') -Raw -Encoding utf8
$just = Get-Content -LiteralPath (Join-Path $repo 'Justfile') -Raw -Encoding utf8

if ($start -notmatch 'Resolve-WinMintWindowsTerminal') { throw 'Start-SmokeElevated must resolve wt' }
if ($start -notmatch 'ArgumentList\.Add') { throw 'Start-SmokeElevated must use ProcessStartInfo.ArgumentList' }
if ($start -notmatch "'-w',\s*'0'") { throw 'Start-SmokeElevated must open a new wt window (-w 0)' }
if ($start -notmatch 'sudo') { throw 'Start-SmokeElevated must elevate via sudo when not admin' }
if ($start -notmatch 'ElevatedWorker') { throw 'Start-SmokeElevated must own -ElevatedWorker process body' }
if ($start -notmatch 'Invoke-SmokeRecipe\.ps1') { throw 'Start-SmokeElevated worker must invoke Recipe in-process' }
if ($start -notmatch 'WT_SESSION') { throw 'Start-SmokeElevated must detect an existing Windows Terminal session' }
if ($start -match '& pwsh -NoProfile -File \$recipe') {
    throw 'Start-SmokeElevated must not nest pwsh.exe for the recipe (conhost)'
}

if ($elev -notmatch 'Start-SmokeElevated\.ps1') { throw 'Invoke-SmokeElevated must shim to Start-SmokeElevated' }
if ($elev -notmatch 'ElevatedWorker') { throw 'Invoke-SmokeElevated shim must pass -ElevatedWorker' }

if ($just -notmatch 'Start-SmokeElevated\.ps1') { throw 'just smoke-maintainer* must use Start-SmokeElevated' }
if ($just -notmatch 'smoke-maintainer-skip-apply') { throw 'Justfile must expose smoke-maintainer-skip-apply' }
if ($just -notmatch "-SkipApply") { throw 'smoke-maintainer-skip-apply must pass -SkipApply' }
if ($start -notmatch '\[switch\] \$SkipApply') { throw 'Start-SmokeElevated must accept -SkipApply' }
if ($recipe -notmatch '\[switch\] \$SkipApply') { throw 'Invoke-SmokeRecipe must accept -SkipApply' }
if ($recipe -notmatch "'-SkipApply'") { throw 'Invoke-SmokeRecipe must forward -SkipApply to Invoke-Smoke' }

if ($recipe -notmatch 'maintainer-host\.json') {
    throw 'Invoke-SmokeRecipe -Maintainer must read maintainer-host.json'
}
if ($recipe -notmatch 'Iso is required unless -Maintainer') {
    throw 'Invoke-SmokeRecipe must require Iso unless -Maintainer'
}

$fixture = Get-Content -LiteralPath (Join-Path $repo 'tests/fixtures/maintainer-host.json') -Raw -Encoding utf8 |
    ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace([string]$fixture.sourceIso.path)) {
    throw 'maintainer-host.json sourceIso.path must be non-empty'
}

$recipePath = Join-Path $repo 'tools/vm/Invoke-SmokeRecipe.ps1'
$err = & pwsh -NoProfile -Command {
    param($Path)
    $ErrorActionPreference = 'Stop'
    try {
        & $Path -Iso ''
        exit 0
    }
    catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 2
    }
} -Args $recipePath 2>&1
if ($LASTEXITCODE -eq 0) {
    throw 'Invoke-SmokeRecipe without Iso/-Maintainer must fail'
}
if ("$err" -notmatch 'Iso is required') {
    throw "expected Iso required message, got: $err"
}

Write-Host 'Test-SmokeElevatedLaunch ok'
