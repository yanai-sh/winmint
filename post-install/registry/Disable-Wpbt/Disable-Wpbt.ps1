#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Stop firmware from running a program out of the Windows Platform Binary Table.
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

Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution' 1

if ($DryRun) {
    Write-Output 'dry-run: WPBT not written.'
}
else {
    Write-Output 'WPBT execution off.'
}
