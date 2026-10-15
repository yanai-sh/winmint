#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Stop Windows from downloading device companion apps.
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

Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1

if ($DryRun) {
    Write-Output 'dry-run: device companion apps not written.'
}
else {
    Write-Output 'Device companion apps blocked.'
}
