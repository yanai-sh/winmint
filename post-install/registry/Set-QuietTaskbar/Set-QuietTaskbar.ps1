#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Hide taskbar search, task view, chat, Copilot, widgets, and Start suggestions.
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

$pol = 'HKLM:\SOFTWARE\Policies\Microsoft'
Set-RegDword "$pol\Dsh" 'AllowNewsAndInterests' 0
Set-RegDword "$pol\Windows\Explorer" 'HideTaskViewButton' 1
Set-RegDword "$pol\Windows\Explorer" 'DisableSearchBoxSuggestions' 1
Set-RegDword "$pol\Windows\Windows Search" 'SearchOnTaskbarMode' 0
Set-RegDword "$pol\Windows\Windows Chat" 'ChatIcon' 3

$cv = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion'
foreach ($pair in @(
        @{ Name = 'TaskbarDa'; Value = 0 }
        @{ Name = 'TaskbarEndTask'; Value = 1 }
        @{ Name = 'Start_IrisRecommendations'; Value = 0 }
        @{ Name = 'ShowTaskViewButton'; Value = 0 }
        @{ Name = 'TaskbarMn'; Value = 0 }
        @{ Name = 'ShowCopilotButton'; Value = 0 }
        @{ Name = 'Start_AccountNotifications'; Value = 0 }
    )) {
    Set-RegDword "$cv\Explorer\Advanced" $pair.Name $pair.Value
}

Set-RegDword "$cv\Search" 'SearchboxTaskbarMode' 0
Set-RegDword "$cv\SearchSettings" 'IsDynamicSearchBoxEnabled' 0

if ($DryRun) {
    Write-Output 'dry-run: quiet taskbar not written.'
}
else {
    Write-Output 'Quiet taskbar applied. Sign out and back in.'
}
