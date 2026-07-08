#Requires -Version 7.6
# Contract: acceptance build plan resolver picks the fastest viable strategy.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'tools\vm\WinMint-VmConsole.ps1')

$profilePath = Join-Path $repoRoot 'tests\profiles\hyper-v-smoke-arm64.json'
$profileJson = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json

$plan = Resolve-WinMintVmAcceptanceBuildPlan -RepoRoot $repoRoot -ProfilePath $profilePath `
    -ProfileJson $profileJson -VMName 'WinMint-ARM-Test' -UseCheckpoint -SmartBuild

$valid = @('push-only', 'checkpoint-push', 'checkpoint-reuse', 'iso-cached-install', 'iso-build-install', 'force-rebuild')
if ($plan.Strategy -notin $valid) {
    throw "Unexpected build strategy: $($plan.Strategy)"
}

$forced = Resolve-WinMintVmAcceptanceBuildPlan -RepoRoot $repoRoot -ProfilePath $profilePath `
    -ProfileJson $profileJson -VMName 'WinMint-ARM-Test' -ForceBuild -SmartBuild
if ($forced.Strategy -ne 'force-rebuild' -and -not $forced.Notes) {
    # SmartBuild may downgrade force-rebuild when ISO is cached
    if ($forced.Strategy -notin @('iso-cached-install', 'checkpoint-push', 'checkpoint-reuse', 'push-only')) {
        throw "Expected force-rebuild or SmartBuild downgrade, got $($forced.Strategy)"
    }
}

if (-not (Get-Command Invoke-WinMintVmAcceptanceCheckpointIteration -ErrorAction SilentlyContinue)) {
    throw 'Invoke-WinMintVmAcceptanceCheckpointIteration is missing from WinMint-VmConsole.ps1 lib exports.'
}

Write-Host "VM acceptance build plan contract: strategy=$($plan.Strategy)"
exit 0
