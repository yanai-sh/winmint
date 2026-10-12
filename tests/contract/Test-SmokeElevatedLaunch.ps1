#requires -Version 7.6
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$start = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Start-SmokeElevated.ps1') -Raw -Encoding utf8
$console = Get-Content -LiteralPath (Join-Path $repo 'tools/host/WinMintHostConsole.ps1') -Raw -Encoding utf8
$elev = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Invoke-SmokeElevated.ps1') -Raw -Encoding utf8
$recipe = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Invoke-SmokeRecipe.ps1') -Raw -Encoding utf8
$just = Get-Content -LiteralPath (Join-Path $repo 'Justfile') -Raw -Encoding utf8

if ($start -notmatch 'Start-WinMintHostConsole') { throw 'Start-SmokeElevated must call Start-WinMintHostConsole' }
if ($start -notmatch '\-Elevate') { throw 'Start-SmokeElevated must pass -Elevate to the host console module' }
if ($start -match 'function Start-WinMintArgvProcess') { throw 'Start-SmokeElevated must not define Start-WinMintArgvProcess' }
if ($console -notmatch 'function Start-WinMintHostConsole') { throw 'WinMintHostConsole must export Start-WinMintHostConsole' }
if ($console -notmatch '\$ProcessStarter') { throw 'WinMintHostConsole must expose ProcessStarter for behavioural contracts' }
if ($start -notmatch 'childExitedEarly') { throw 'Start-SmokeElevated must throw childExitedEarly when elevated worker pid file never appears' }
if ($start -notmatch 'Test-WinMintHostConsoleWorkerPidAlive') { throw 'Start-SmokeElevated spawn wait must poll worker pid file' }
if ($console -notmatch 'host-console-worker\.pid') { throw 'WinMintHostConsole must define host-console-worker.pid path' }
if ($console -notmatch 'Test-WinMintHostConsoleWorkerPidAlive') { throw 'WinMintHostConsole overlap must prefer worker pid file' }
if ($start -notmatch 'ElevatedWorker') { throw 'Start-SmokeElevated must own -ElevatedWorker process body' }
if ($start -notmatch 'Invoke-SmokeRecipe\.ps1') { throw 'Start-SmokeElevated worker must invoke Recipe in-process' }
if ($console -notmatch 'WT_SESSION') { throw 'WinMintHostConsole must detect an existing Windows Terminal session' }
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
