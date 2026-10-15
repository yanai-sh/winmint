#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Block OneDrive sync. Does not uninstall OneDrive.
.DESCRIPTION
  Maintainer working tree. Not ready for anyone else to run.
  Windows PowerShell 5.1 and PowerShell 7. Run elevated.
  -DryRun prints each value and writes nothing.
#>
param([switch] $DryRun)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
    $PSNativeCommandUseErrorActionPreference = $false
}

. (Join-Path $PSScriptRoot 'Registry.ps1')

$pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
Set-RegDword $pol 'DisableFileSyncNGSC' 1
Set-RegDword $pol 'DisableFileSync' 1
Set-RegDword $pol 'DisableMeteredNetworkFileSync' 1
Set-RegDword $pol 'PreventNetworkTrafficPreUserSignIn' 1
Set-RegDword 'HKLM:\SOFTWARE\Microsoft\OneDrive' 'PreventNetworkTrafficPreUserSignIn' 1

if ($DryRun) {
    Write-Output 'dry-run: OneDrive policy not written.'
}
else {
    Write-Output 'OneDrive sync blocked.'
}
