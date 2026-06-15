#Requires -Version 7.3
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$testRoot = $PSScriptRoot

foreach ($testScript in @(
        'Test-ProfileInvariants.ps1',
        'Test-InstallPlanContract.ps1',
        'Test-PayloadStoreContract.ps1',
        'Test-CliMatrix.ps1',
        'Test-FirstLogonTransactionPlan.ps1',
        'Test-AgentStateTransitions.ps1',
        'Test-BootstrapContract.ps1',
        'Test-CloudflareWorkerContract.ps1',
        'Test-UiContractSpine.ps1',
        'Test-ServicedWimCache.ps1'
    )) {
    & (Join-Path $testRoot $testScript)
}

Write-Host 'Fast test suite passed.'
