#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Turn on Developer Mode.
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

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Registry.ps1')

Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' 'AllowDevelopmentWithoutDevLicense' 1

if ($DryRun) {
    Write-Output 'dry-run: Developer Mode not written.'
}
else {
    Write-Output 'Developer Mode on.'
}
