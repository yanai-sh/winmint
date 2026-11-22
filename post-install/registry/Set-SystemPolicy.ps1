#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Activity history, update peering, companion apps, WPBT, Store notify, long paths, Developer Mode, sudo, and XDG directories.
.DESCRIPTION
  Maintainer working tree. Not ready for anyone else to run.
  Windows PowerShell 5.1 and PowerShell 7. Run elevated.
  This file stands alone. The working directory does not matter. A second run writes the same values.
  Activity history is off. Clipboard history is left alone.
  Updates still download from Microsoft. This PC does not peer them.
  -DryRun prints each value and writes nothing.
#>
param([switch] $DryRun)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
    $PSNativeCommandUseErrorActionPreference = $false
}

$regExe = Join-Path $PSScriptRoot 'Set-RegExeValue.ps1'

$system = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
& $regExe -Path $system -Name 'EnableActivityFeed' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path $system -Name 'PublishUserActivities' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path $system -Name 'UploadUserActivities' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Name 'DODownloadMode' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' -Name 'PreventDeviceMetadataFromNetwork' -Type 'REG_DWORD' -Data '1' -DryRun:$DryRun
& $regExe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'DisableWpbtExecution' -Type 'REG_DWORD' -Data '1' -DryRun:$DryRun
& $regExe -Path 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' -Name 'AutoDownload' -Type 'REG_DWORD' -Data '2' -DryRun:$DryRun
& $regExe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Type 'REG_DWORD' -Data '1' -DryRun:$DryRun
& $regExe -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowDevelopmentWithoutDevLicense' -Type 'REG_DWORD' -Data '1' -DryRun:$DryRun
& $regExe -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo' -Name 'Enabled' -Type 'REG_DWORD' -Data '3' -DryRun:$DryRun
& $regExe -Path 'HKCU:\Environment' -Name 'XDG_CONFIG_HOME' -Type 'REG_EXPAND_SZ' -Data '%USERPROFILE%\.config' -DryRun:$DryRun
& $regExe -Path 'HKCU:\Environment' -Name 'XDG_DATA_HOME' -Type 'REG_EXPAND_SZ' -Data '%USERPROFILE%\.local\share' -DryRun:$DryRun
& $regExe -Path 'HKCU:\Environment' -Name 'XDG_STATE_HOME' -Type 'REG_EXPAND_SZ' -Data '%USERPROFILE%\.local\state' -DryRun:$DryRun
& $regExe -Path 'HKCU:\Environment' -Name 'XDG_CACHE_HOME' -Type 'REG_EXPAND_SZ' -Data '%USERPROFILE%\.cache' -DryRun:$DryRun

if ($DryRun) {
    Write-Output 'dry-run: system policy not written.'
}
else {
    Write-Output 'System policy applied. Sign out and back in.'
}
