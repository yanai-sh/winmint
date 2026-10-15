#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Dark theme, visible extensions and hidden files, full path, and a plain desktop.
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


function Set-RegDword {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][int] $Value)
    if ($DryRun) {
        Write-Output "dry-run: $Path $Name = $Value"
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Set-RegString {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][string] $Value)
    if ($DryRun) {
        Write-Output "dry-run: $Path $Name = $Value"
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType String -Force | Out-Null
}

function Set-RegExpand {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][string] $Value)
    if ($DryRun) {
        Write-Output "dry-run: $Path $Name = $Value"
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType ExpandString -Force | Out-Null
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
