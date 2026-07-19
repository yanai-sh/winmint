#Requires -Version 7.6
<#
.SYNOPSIS
    SetupComplete action dispatch must load Invoke-Sc* into script scope and
    skip catalog rows with empty FunctionName (inline-only steps).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-ScDispatchFailure {
    param([string]$Message)
    $script:failures.Add($Message) | Out-Null
}

$setupRoot = Join-Path $root 'src\runtime\setup'
. (Join-Path $setupRoot 'Setup.Actions.ps1')

$emptyNameActions = @(
    Get-WinMintSetupActionCatalog |
        Where-Object { [string]::IsNullOrWhiteSpace([string]$_.FunctionName) } |
        ForEach-Object { [string]$_.Id }
)
foreach ($expectedInline in @('first-logon-runonce', 'inline-secret-cleanup')) {
    if ($emptyNameActions -notcontains $expectedInline) {
        Add-ScDispatchFailure "Catalog action '$expectedInline' must use empty FunctionName (inline-only)."
    }
}

# Historical bug: Import ran `. $modulePath` inside a helper function, so module
# functions landed in that function's local scope and vanished before the action loop.
# Promoting only Invoke-Sc* still stranded helpers (Resolve-ScPowerPlanActivation).
foreach ($name in @(
        'Invoke-ScTimeSync',
        'Invoke-ScPowerProfile',
        'Invoke-ScAutoLogonStamp',
        'Resolve-ScPowerPlanActivation',
        'Get-ScPowerPlanCatalog',
        'Resolve-ScWingetExePath'
    )) {
    Remove-Item -LiteralPath "Function:$name" -ErrorAction SilentlyContinue
}
Import-WinMintSetupActionModules -PayloadRoot $setupRoot
if (Get-Command Invoke-ScEdgeRemoval -ErrorAction SilentlyContinue) {
    Add-ScDispatchFailure 'Invoke-ScEdgeRemoval must not exist; Edge uninstall is not a SetupComplete product path.'
}
if (@(Get-WinMintSetupActionCatalog | Where-Object { [string]$_.Id -eq 'edge-removal' }).Count -gt 0) {
    Add-ScDispatchFailure 'Setup action catalog must not include edge-removal.'
}
if (-not (Get-Command Invoke-ScTimeSync -ErrorAction SilentlyContinue)) {
    Add-ScDispatchFailure 'Import-WinMintSetupActionModules must expose Invoke-ScTimeSync after return.'
}
if (-not (Get-Command Invoke-ScAutoLogonStamp -ErrorAction SilentlyContinue)) {
    Add-ScDispatchFailure 'Import-WinMintSetupActionModules must expose Invoke-ScAutoLogonStamp (defaultuser0 Winlogon restamp).'
}
if (-not (Get-Command Resolve-ScPowerPlanActivation -ErrorAction SilentlyContinue)) {
    Add-ScDispatchFailure 'Import-WinMintSetupActionModules must promote helpers (Resolve-ScPowerPlanActivation), not only Invoke-Sc*.'
}
if (-not (Get-Command Resolve-ScWingetExePath -ErrorAction SilentlyContinue)) {
    Add-ScDispatchFailure 'Import-WinMintSetupActionModules must promote Resolve-ScWingetExePath for toolchain installs.'
}
if (-not (Get-Command Invoke-ScOobeRehydrationSuppression -ErrorAction SilentlyContinue)) {
    Add-ScDispatchFailure 'Import-WinMintSetupActionModules must expose Invoke-ScOobeRehydrationSuppression.'
}
$catalogIds = @(Get-WinMintSetupActionCatalog | ForEach-Object { [string]$_.Id })
$autoLogonIdx = $catalogIds.IndexOf('autologon-stamp')
$toolchainIdx = $catalogIds.IndexOf('toolchain-install')
$runOnceIdx = $catalogIds.IndexOf('first-logon-runonce')
if ($autoLogonIdx -lt 0) {
    Add-ScDispatchFailure 'Catalog must include autologon-stamp.'
}
elseif ($toolchainIdx -ge 0 -and $autoLogonIdx -gt $toolchainIdx) {
    Add-ScDispatchFailure 'autologon-stamp must run before toolchain-install so defaultuser0 cannot hang FirstLogonAnim while winget blocks.'
}
elseif ($runOnceIdx -ge 0 -and $autoLogonIdx -lt $runOnceIdx) {
    Add-ScDispatchFailure 'autologon-stamp should run after first-logon-runonce registration.'
}
$toolchainText = Get-Content -LiteralPath (Join-Path $setupRoot 'SetupComplete\Toolchain.ps1') -Raw
if ($toolchainText -notmatch 'WaitForExit') {
    Add-ScDispatchFailure 'Toolchain winget install must use a bounded WaitForExit timeout.'
}

$dispatchText = Get-Content -LiteralPath (Join-Path $setupRoot 'SetupComplete.ps1') -Raw
if ($dispatchText -notmatch 'IsNullOrWhiteSpace\(\[string\]\$_\.FunctionName\)') {
    Add-ScDispatchFailure 'SetupComplete.ps1 must skip catalog actions with empty FunctionName before calling & $action.FunctionName.'
}
if ($dispatchText -match "SetupComplete_errors\.log'\)\s*-Force") {
    Add-ScDispatchFailure 'SetupComplete.ps1 must Append action errors (not -Force overwrite) so module-load failures stay visible.'
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}

Write-Host 'SetupComplete action dispatch contract: OK'
exit 0
