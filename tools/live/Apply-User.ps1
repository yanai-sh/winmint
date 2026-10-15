#requires -Version 5.1
<#
.SYNOPSIS
  Curated WinMint first-logon registry for the account that runs it.
.DESCRIPTION
  Run from Windows PowerShell after Apply-Machine.ps1 and after Windows Update.
  Sign out and back in. A feature update can put taskbar buttons back; run this again.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Set-RegDword {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][int] $Value)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Set-RegExpand {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][string] $Value)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType ExpandString -Force | Out-Null
}

$cv = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion'
Set-RegDword "$cv\Themes\Personalize" 'AppsUseLightTheme' 0
Set-RegDword "$cv\Themes\Personalize" 'SystemUsesLightTheme' 0
Set-RegDword "$cv\Notifications\Settings" 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' 0

$advanced = @{
    HideFileExt                    = 0
    Hidden                         = 1
    FullPathAddress                = 1
    LaunchTo                       = 1
    ShowFrequent                   = 0
    NavPaneShowVersionControl      = 1
    ShowSyncProviderNotifications  = 0
    TaskbarDa                      = 0
    TaskbarEndTask                 = 1
    Start_IrisRecommendations      = 0
    ShowTaskViewButton             = 0
    TaskbarMn                      = 0
    ShowCopilotButton              = 0
    Start_AccountNotifications     = 0
}
foreach ($name in $advanced.Keys) {
    Set-RegDword "$cv\Explorer\Advanced" $name $advanced[$name]
}

Set-RegDword "$cv\Explorer" 'ShowRecent' 0
Set-RegDword "$cv\Explorer" 'ShowCloudFilesInQuickAccess' 0
Set-RegDword "$cv\Search" 'SearchboxTaskbarMode' 0
Set-RegDword "$cv\SearchSettings" 'IsDynamicSearchBoxEnabled' 0
Set-RegDword "$cv\DesktopSpotlight\Settings" 'EnabledState' 0
Set-RegDword "$cv\Explorer\Wallpapers" 'BackgroundType' 0

$hide = '{645FF040-5081-101B-9F08-00AA002F954E}'
Set-RegDword "$cv\Explorer\HideDesktopIcons\NewStartPanel" $hide 1
Set-RegDword "$cv\Explorer\HideDesktopIcons\ClassicStartMenu" $hide 1

foreach ($name in @(
        'SubscribedContent-310093Enabled'
        'SubscribedContent-338388Enabled'
        'SubscribedContent-338389Enabled'
        'SubscribedContent-338393Enabled'
        'SubscribedContent-353694Enabled'
        'SubscribedContent-353696Enabled'
        'SubscribedContent-353698Enabled'
        'SoftLandingEnabled'
        'SystemPaneSuggestionsEnabled'
        'SilentInstalledAppsEnabled'
        'PreInstalledAppsEnabled'
        'OemPreInstalledAppsEnabled'
        'RotatingLockScreenEnabled'
        'RotatingLockScreenOverlayEnabled'
    )) {
    Set-RegDword "$cv\ContentDeliveryManager" $name 0
}

$folders = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
Set-RegExpand $folders 'Desktop' '%USERPROFILE%\Desktop'
Set-RegExpand $folders 'Personal' '%USERPROFILE%\Documents'
Set-RegExpand $folders 'My Pictures' '%USERPROFILE%\Pictures'
Set-RegExpand $folders 'My Music' '%USERPROFILE%\Music'
Set-RegExpand $folders 'My Video' '%USERPROFILE%\Videos'
Set-RegExpand $folders 'Favorites' '%USERPROFILE%\Favorites'
Set-RegExpand $folders '{374DE290-123F-4565-9164-39C4925E467B}' '%USERPROFILE%\Downloads'
Set-RegExpand $folders '{F42EE2D3-909F-4907-8871-4C22FC0BF756}' '%USERPROFILE%\Documents'
Set-RegExpand $folders '{0DDD015D-B06C-45D5-8C4C-F59713854639}' '%USERPROFILE%\Pictures'
Set-RegExpand $folders '{A0C69A99-21C8-4671-8703-7934162FCF1D}' '%USERPROFILE%\Music'
Set-RegExpand $folders '{35286A68-3C57-41A1-BBB1-0EAE73D76C95}' '%USERPROFILE%\Videos'
Set-RegExpand $folders '{754AC886-DF64-4CBA-86B5-F7FBF4FBCEF5}' '%USERPROFILE%\Desktop'

Set-RegExpand 'HKCU:\Environment' 'XDG_CONFIG_HOME' '%USERPROFILE%\.config'
Set-RegExpand 'HKCU:\Environment' 'XDG_DATA_HOME' '%USERPROFILE%\.local\share'
Set-RegExpand 'HKCU:\Environment' 'XDG_STATE_HOME' '%USERPROFILE%\.local\state'
Set-RegExpand 'HKCU:\Environment' 'XDG_CACHE_HOME' '%USERPROFILE%\.cache'

Write-Output 'User posture applied. Sign out and back in.'
