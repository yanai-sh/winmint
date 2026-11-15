#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Hide taskbar search, task view, chat, Copilot, widgets, and Start suggestions.
.DESCRIPTION
  Maintainer working tree. Not ready for anyone else to run.
  Windows PowerShell 5.1 and PowerShell 7. Run elevated.
  This file stands alone. The working directory does not matter. A second run writes the same values.
  Widgets and taskbar search values are written with reg.exe, which Windows allows to change them.
  -DryRun prints each value and writes nothing.
#>
param([switch] $DryRun)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
    $PSNativeCommandUseErrorActionPreference = $false
}

$regExe = Join-Path $PSScriptRoot 'Set-RegExeValue.ps1'

$pol = 'HKLM:\SOFTWARE\Policies\Microsoft'
& $regExe -Path "$pol\Dsh" -Name 'AllowNewsAndInterests' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path "$pol\Windows\Explorer" -Name 'HideTaskViewButton' -Type 'REG_DWORD' -Data '1' -DryRun:$DryRun
& $regExe -Path "$pol\Windows\Explorer" -Name 'DisableSearchBoxSuggestions' -Type 'REG_DWORD' -Data '1' -DryRun:$DryRun
& $regExe -Path "$pol\Windows\Windows Search" -Name 'SearchOnTaskbarMode' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path "$pol\Windows\Windows Chat" -Name 'ChatIcon' -Type 'REG_DWORD' -Data '3' -DryRun:$DryRun

$cv = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion'
foreach ($pair in @(
        @{ Name = 'TaskbarDa'; Value = '0' }
        @{ Name = 'TaskbarEndTask'; Value = '1' }
        @{ Name = 'Start_IrisRecommendations'; Value = '0' }
        @{ Name = 'ShowTaskViewButton'; Value = '0' }
        @{ Name = 'TaskbarMn'; Value = '0' }
        @{ Name = 'ShowCopilotButton'; Value = '0' }
        @{ Name = 'Start_AccountNotifications'; Value = '0' }
    )) {
    & $regExe -Path "$cv\Explorer\Advanced" -Name $pair.Name -Type 'REG_DWORD' -Data $pair.Value -DryRun:$DryRun
}

& $regExe -Path "$cv\Search" -Name 'SearchboxTaskbarMode' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path "$cv\SearchSettings" -Name 'IsDynamicSearchBoxEnabled' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun

if ($DryRun) {
    Write-Output 'dry-run: quiet taskbar not written.'
}
else {
    Write-Output 'Quiet taskbar applied. Sign out and back in.'
}
