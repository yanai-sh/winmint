#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Turn activity history off. Leaves clipboard history alone.
.DESCRIPTION
  Maintainer working tree. Not ready for anyone else to run.
  Windows PowerShell 5.1 and PowerShell 7. Run elevated.
  The feed, publish, and upload policies are all 0.
  -DryRun prints each value and writes nothing.
#>
param([switch] $DryRun)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
    $PSNativeCommandUseErrorActionPreference = $false
}

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Registry.ps1')

$pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
Set-RegDword $pol 'EnableActivityFeed' 0
Set-RegDword $pol 'PublishUserActivities' 0
Set-RegDword $pol 'UploadUserActivities' 0

if ($DryRun) {
    Write-Output 'dry-run: activity history not written.'
}
else {
    Write-Output 'Activity history off.'
}
