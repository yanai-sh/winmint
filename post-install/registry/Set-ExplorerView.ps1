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
    $output = & $reg add $regPath /v $Name /t $Type /d $Data /f 2>&1
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


$cv = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion'
Set-RegDword "$cv\Themes\Personalize" 'AppsUseLightTheme' 0
Set-RegDword "$cv\Themes\Personalize" 'SystemUsesLightTheme' 0
Set-RegDword "$cv\Notifications\Settings" 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' 0

foreach ($pair in @(
        @{ Name = 'HideFileExt'; Value = 0 }
        @{ Name = 'Hidden'; Value = 1 }
        @{ Name = 'FullPathAddress'; Value = 1 }
        @{ Name = 'LaunchTo'; Value = 1 }
        @{ Name = 'ShowFrequent'; Value = 0 }
        @{ Name = 'NavPaneShowVersionControl'; Value = 1 }
        @{ Name = 'ShowSyncProviderNotifications'; Value = 0 }
    )) {
    Set-RegDword "$cv\Explorer\Advanced" $pair.Name $pair.Value
}

Set-RegDword "$cv\Explorer" 'ShowRecent' 0
Set-RegDword "$cv\Explorer" 'ShowCloudFilesInQuickAccess' 0
Set-RegDword "$cv\DesktopSpotlight\Settings" 'EnabledState' 0
Set-RegDword "$cv\Explorer\Wallpapers" 'BackgroundType' 0

$hide = '{645FF040-5081-101B-9F08-00AA002F954E}'
Set-RegDword "$cv\Explorer\HideDesktopIcons\NewStartPanel" $hide 1
Set-RegDword "$cv\Explorer\HideDesktopIcons\ClassicStartMenu" $hide 1

if ($DryRun) {
    Write-Output 'dry-run: Explorer view not written.'
}
else {
    Write-Output 'Explorer view applied. Sign out and back in.'
}
