#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Run the live posture scripts in order.
.DESCRIPTION
  Windows PowerShell 5.1 and PowerShell 7. Run elevated from this directory, after Windows Update.
  Each script also runs on its own.
  -DryRun prints the changes and writes nothing.
  -Drivers also installs the Surface catalog MSI. It is off unless you pass it.

  pwsh -NoProfile -File .\Apply-LivePosture.ps1 -DryRun
  pwsh -NoProfile -File .\Apply-LivePosture.ps1 -DryRun -Drivers
  pwsh -NoProfile -File .\Apply-LivePosture.ps1 -Drivers
  powershell -NoProfile -File .\Apply-LivePosture.ps1 -DryRun
#>
param(
    [switch] $DryRun,
    [switch] $Drivers,
    [string] $DeviceId = 'surface-laptop-7'
)

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
    if ($DryRun) {
        & $path -DryRun
    }
    else {
        & $path
    }
}

if ($Drivers) {
    $driverScript = Join-Path $PSScriptRoot 'Install-SurfaceDrivers.ps1'
    Write-Output 'live: Install-SurfaceDrivers.ps1'
    if ($DryRun) {
        & $driverScript -DryRun -DeviceId $DeviceId
    }
    else {
        & $driverScript -DeviceId $DeviceId
    }
}
elseif ($DryRun) {
    Write-Output 'dry-run: Surface drivers skipped. Pass -Drivers to include them.'
}

if ($DryRun) {
    Write-Output 'dry-run: live posture not applied.'
}
else {
    Write-Output 'Live posture applied. Sign out and back in.'
}
