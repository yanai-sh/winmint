#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Run the registry scripts.
.DESCRIPTION
  Maintainer working tree. Not ready for anyone else to run.
  Windows PowerShell 5.1 and PowerShell 7. Run elevated, after Windows Update.
  Each script in registry\ also runs on its own.
  Sign out afterward. Leaves UAC, Reserved Storage, language, home region, and time zone alone.
  -DryRun prints each value and writes nothing.
#>
param([switch] $DryRun)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
    $PSNativeCommandUseErrorActionPreference = $false
}

$registry = Join-Path $PSScriptRoot 'registry'
foreach ($name in @(
        'Disable-ConsumerFeatures.ps1'
        'Set-QuietTaskbar.ps1'
        'Disable-EdgePromotions.ps1'
        'Set-ExplorerView.ps1'
        'Set-SystemPolicy.ps1'
    )) {
    $path = Join-Path $registry $name
    Write-Output "registry: $name"
    if ($DryRun) {
        & $path -DryRun
    }
    else {
        & $path
    }
}

if ($DryRun) {
    Write-Output 'dry-run: registry not written.'
}
else {
    Write-Output 'Registry applied. Sign out and back in.'
}
