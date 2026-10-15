#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Download updates from Microsoft only. This PC does not peer them.
.DESCRIPTION
  Maintainer working tree. Not ready for anyone else to run.
  Windows PowerShell 5.1 and PowerShell 7. Run elevated.
  DODownloadMode 0 keeps HTTP downloads and turns peering off.
  -DryRun prints each value and writes nothing.
#>
param([switch] $DryRun)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
    $PSNativeCommandUseErrorActionPreference = $false
}

. (Join-Path $PSScriptRoot 'Registry.ps1')

Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0

if ($DryRun) {
    Write-Output 'dry-run: Delivery Optimization not written.'
}
else {
    Write-Output 'Delivery Optimization peering off.'
}
