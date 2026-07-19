#Requires -Version 7.6
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path -LiteralPath (Join-Path $root 'src\runtime\setup\SetupComplete\OobeRehydration.ps1'))) {
    $root = Split-Path -Parent $PSScriptRoot
}

$text = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\SetupComplete\OobeRehydration.ps1') -Raw
$failures = [System.Collections.Generic.List[string]]::new()
function Add-OobeFailure([string]$Message) { $failures.Add($Message) | Out-Null }

foreach ($expected in @(
        'WinMintKnownOobeRehydrationJobs',
        'OutlookUpdate',
        'DevHomeUpdate',
        'ChatAutoInstall',
        'BlockedOobeUpdaters',
        'MS_Outlook',
        'enumeratedKeys',
        'leftAlone',
        'suppressed',
        'SetupComplete_OobeRehydration.json',
        'Get-ChildItem'
    )) {
    if ($text -notmatch [regex]::Escape($expected)) {
        Add-OobeFailure "OOBE rehydration suppression should contain '$expected'."
    }
}

if ($text -notmatch 'learn-control-install-new-outlook') {
    Add-OobeFailure 'OutlookUpdate must be marked as Microsoft-documented.'
}
if ($text -notmatch 'Left unknown OOBE rehydration key alone') {
    Add-OobeFailure 'Unknown Orchestrator keys must be left alone, not deleted.'
}

$actionsText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\Setup.Actions.ps1') -Raw
if ($actionsText -notmatch 'Invoke-ScOobeRehydrationSuppression') {
    Add-OobeFailure 'Setup.Actions must dispatch Invoke-ScOobeRehydrationSuppression.'
}

if ($failures.Count -gt 0) {
    Write-Host 'OOBE rehydration contract: FAIL'
    $failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}
Write-Host 'OOBE rehydration contract: OK'
exit 0
