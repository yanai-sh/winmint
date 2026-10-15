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


function Set-RegValue {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Type,
        [Parameter(Mandatory)][string] $Data
    )
    if ($DryRun) {
        Write-Output "dry-run: $Path $Name = $Data"
        return
    }

    if ($Path -notmatch '^(HKLM|HKCU):\\(.+)$') {
        throw "Unsupported registry path: $Path"
    }

    $regPath = $Matches[1] + '\' + $Matches[2]
    $reg = Join-Path $env:SystemRoot 'System32\reg.exe'
    # Redirected native stderr ends the script on Windows PowerShell 5.1 while Stop is in effect.
    $ErrorActionPreference = 'Continue'
    $output = & $reg add $regPath /v $Name /t $Type /d $Data /f 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -eq 0) {
        return
    }

    $text = (@($output) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join ' '
    if ($text -match 'Access is denied') {
        Write-Output "left unchanged: $regPath $Name"
        return
    }

    throw "Could not set $regPath $Name ($LASTEXITCODE). $text"
}

function Set-RegDword {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][int] $Value)
    Set-RegValue -Path $Path -Name $Name -Type 'REG_DWORD' -Data "$Value"
}

function Set-RegString {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][string] $Value)
    Set-RegValue -Path $Path -Name $Name -Type 'REG_SZ' -Data $Value
}

function Set-RegExpand {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][string] $Value)
    Set-RegValue -Path $Path -Name $Name -Type 'REG_EXPAND_SZ' -Data $Value
}


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
