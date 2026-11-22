#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Dark theme, visible extensions and hidden files, full path, and a plain desktop.
.DESCRIPTION
  Maintainer working tree. Not ready for anyone else to run.
  Windows PowerShell 5.1 and PowerShell 7. Run elevated.
  This file stands alone. The working directory does not matter. A second run writes the same values.
  -DryRun prints each value and writes nothing.
#>
param([switch] $DryRun)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
    $PSNativeCommandUseErrorActionPreference = $false
}

$regExe = Join-Path $PSScriptRoot 'Set-RegExeValue.ps1'

$cv = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion'
& $regExe -Path "$cv\Themes\Personalize" -Name 'AppsUseLightTheme' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path "$cv\Themes\Personalize" -Name 'SystemUsesLightTheme' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path "$cv\Notifications\Settings" -Name 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun

foreach ($pair in @(
        @{ Name = 'HideFileExt'; Value = '0' }
        @{ Name = 'Hidden'; Value = '1' }
        @{ Name = 'FullPathAddress'; Value = '1' }
        @{ Name = 'LaunchTo'; Value = '1' }
        @{ Name = 'ShowFrequent'; Value = '0' }
        @{ Name = 'NavPaneShowVersionControl'; Value = '1' }
        @{ Name = 'ShowSyncProviderNotifications'; Value = '0' }
    )) {
    & $regExe -Path "$cv\Explorer\Advanced" -Name $pair.Name -Type 'REG_DWORD' -Data $pair.Value -DryRun:$DryRun
}

& $regExe -Path "$cv\Explorer" -Name 'ShowRecent' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path "$cv\Explorer" -Name 'ShowCloudFilesInQuickAccess' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path "$cv\DesktopSpotlight\Settings" -Name 'EnabledState' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path "$cv\Explorer\Wallpapers" -Name 'BackgroundType' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun

$hide = '{645FF040-5081-101B-9F08-00AA002F954E}'
& $regExe -Path "$cv\Explorer\HideDesktopIcons\NewStartPanel" -Name $hide -Type 'REG_DWORD' -Data '1' -DryRun:$DryRun
& $regExe -Path "$cv\Explorer\HideDesktopIcons\ClassicStartMenu" -Name $hide -Type 'REG_DWORD' -Data '1' -DryRun:$DryRun

if ($DryRun) {
    Write-Output 'dry-run: Explorer view not written.'
}
else {
    Write-Output 'Explorer view applied. Sign out and back in.'
}
