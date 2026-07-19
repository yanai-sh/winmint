#Requires -Version 7.6
<#
.SYNOPSIS
  Red/green check: SetupComplete module helpers must survive Import-WinMintSetupActionModules.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$setupRoot = Join-Path $root 'src\runtime\setup'
. (Join-Path $setupRoot 'Setup.Actions.ps1')

foreach ($name in @(
        'Resolve-ScPowerPlanActivation',
        'Get-ScPowerPlanCatalog',
        'Find-ScPowerSchemeGuidByName',
        'Invoke-ScPowerProfile'
    )) {
    Remove-Item -LiteralPath "Function:$name" -ErrorAction SilentlyContinue
}

Import-WinMintSetupActionModules -PayloadRoot $setupRoot

if (Get-Command -Name 'Invoke-ScEdgeRemoval' -ErrorAction SilentlyContinue) {
    Write-Host 'FAIL Invoke-ScEdgeRemoval must not exist (Edge uninstall is not a product path).'
    exit 1
}

$missing = [System.Collections.Generic.List[string]]::new()
foreach ($name in @(
        'Resolve-ScPowerPlanActivation',
        'Get-ScPowerPlanCatalog',
        'Find-ScPowerSchemeGuidByName',
        'Invoke-ScPowerProfile'
    )) {
    if (-not (Get-Command -Name $name -ErrorAction SilentlyContinue)) {
        $missing.Add($name) | Out-Null
    }
}

if ($missing.Count -gt 0) {
    Write-Host ("FAIL missing after Import: " + ($missing -join ', '))
    exit 1
}

# Call path used by Invoke-ScPowerProfile (no powercfg required for resolve).
$activation = Resolve-ScPowerPlanActivation -PowerCfg 'powercfg.exe' -Plan 'Balanced'
if ([string]$activation.Guid -ne '381b4222-f694-41f0-9685-ff5bb260df2e') {
    Write-Host "FAIL unexpected Balanced GUID: $($activation.Guid)"
    exit 1
}

Write-Host 'Assert-WinMintSetupActionHelperScope: OK'
exit 0
