#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Run the live posture scripts in order.
.DESCRIPTION
  Windows PowerShell 5.1 and PowerShell 7. Run elevated from this directory, after Windows Update.
  Each script also runs on its own.

  pwsh -NoProfile -File .\Apply-LivePosture.ps1
  powershell -NoProfile -File .\Apply-LivePosture.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
    $PSNativeCommandUseErrorActionPreference = $false
}

foreach ($name in @(
        'Apply-Registry.ps1'
        'Uninstall-OneDrive.ps1'
        'Remove-InboxApps.ps1'
    )) {
    $path = Join-Path $PSScriptRoot $name
    Write-Output "live: $name"
    & $path
}

Write-Output 'Live posture applied. Sign out and back in.'
