#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Curated WinMint registry, OneDrive uninstall, and the SL7 inbox-app strip.
.DESCRIPTION
  Elevated Windows PowerShell, after Windows Update. Sign out afterward.
  Leaves UAC, language, and time zone alone.
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

function Set-RegString {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][string] $Value)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType String -Force | Out-Null
}

function Set-RegExpand {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][string] $Value)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType ExpandString -Force | Out-Null
}

$pol = 'HKLM:\SOFTWARE\Policies\Microsoft'
Set-RegDword "$pol\Dsh" 'AllowNewsAndInterests' 0
Set-RegDword "$pol\Windows\Explorer" 'HideTaskViewButton' 1
Set-RegDword "$pol\Windows\Explorer" 'DisableSearchBoxSuggestions' 1
Set-RegDword "$pol\Windows\Windows Search" 'SearchOnTaskbarMode' 0
Set-RegDword "$pol\Windows\Windows Chat" 'ChatIcon' 3
Set-RegDword "$pol\Windows\CloudContent" 'DisableWindowsConsumerFeatures' 1
Set-RegDword "$pol\Windows\CloudContent" 'DisableSoftLanding' 1
Set-RegDword "$pol\WindowsStore" 'AutoDownload' 2
Set-RegDword "$pol\Windows\OneDrive" 'DisableFileSyncNGSC' 1
Set-RegDword "$pol\Windows\OneDrive" 'DisableFileSync' 1
Set-RegDword "$pol\Windows\OneDrive" 'DisableMeteredNetworkFileSync' 1
Set-RegDword "$pol\Windows\OneDrive" 'PreventNetworkTrafficPreUserSignIn' 1
Set-RegDword "$pol\Windows\Device Metadata" 'PreventDeviceMetadataFromNetwork' 1

$edge = "$pol\Edge"
Set-RegDword "$pol\EdgeUpdate" 'CreateDesktopShortcutDefault' 0
Set-RegDword $edge 'PersonalizationReportingEnabled' 0
Set-RegString "$edge\ExtensionInstallBlocklist" '1' 'ofefcgjbeghpigppfmkologfjadafddi'
Set-RegDword $edge 'ShowRecommendationsEnabled' 0
Set-RegDword $edge 'HideFirstRunExperience' 1
Set-RegString $edge 'NewTabPageLocation' 'about:blank'
Set-RegDword $edge 'UserFeedbackAllowed' 0
Set-RegDword $edge 'ConfigureDoNotTrack' 1
Set-RegDword $edge 'AlternateErrorPagesEnabled' 0
Set-RegDword $edge 'EdgeCollectionsEnabled' 0
Set-RegDword $edge 'EdgeShoppingAssistantEnabled' 0
Set-RegDword $edge 'MicrosoftEdgeInsiderPromotionEnabled' 0
Set-RegDword $edge 'ShowMicrosoftRewards' 0
Set-RegDword $edge 'WebWidgetAllowed' 0
Set-RegDword $edge 'DiagnosticData' 0
Set-RegDword $edge 'EdgeAssetDeliveryServiceEnabled' 0
Set-RegDword $edge 'WalletDonationEnabled' 0
Set-RegDword $edge 'DefaultBrowserSettingsCampaignEnabled' 0

$soft = 'HKLM:\SOFTWARE\Microsoft'
Set-RegDword "$soft\Windows\CurrentVersion\AppModelUnlock" 'AllowDevelopmentWithoutDevLicense' 1
Set-RegDword "$soft\Windows\CurrentVersion\Sudo" 'Enabled' 3
Set-RegDword "$soft\OneDrive" 'PreventNetworkTrafficPreUserSignIn' 1
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution' 1

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

$folders = "$cv\Explorer\User Shell Folders"
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

function Invoke-OneDriveUninstall {
    $ran = $false
    foreach ($setup in @(
            (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe')
            (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe')
        )) {
        if (-not (Test-Path -LiteralPath $setup)) {
            continue
        }

        $ran = $true
        $proc = Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait -PassThru -WindowStyle Hidden
        Write-Output "OneDriveSetup exit $($proc.ExitCode): $setup"
    }

    if (-not $ran) {
        Write-Output 'OneDriveSetup.exe is not on this PC.'
    }

    foreach ($run in @(
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        )) {
        if (-not (Test-Path -LiteralPath $run)) {
            continue
        }

        $key = Get-Item -LiteralPath $run
        foreach ($name in @($key.GetValueNames())) {
            $value = [string] $key.GetValue($name)
            if ($value -like '*OneDrive*') {
                Remove-ItemProperty -LiteralPath $run -Name $name -ErrorAction SilentlyContinue
            }
        }
    }
}

function Remove-Sl7App {
    param([Parameter(Mandatory)][string] $Id)
    $pfns = New-Object System.Collections.Generic.List[string]
    $installed = @(Get-AppxPackage -AllUsers -Name $Id -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $Id })
    foreach ($pkg in $installed) {
        try {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
        }
        catch {
            Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
        }

        if ($pkg.PackageFamilyName) {
            $pfns.Add($pkg.PackageFamilyName)
        }
    }

    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $Id })
    foreach ($pkg in $provisioned) {
        Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction SilentlyContinue | Out-Null
    }

    if ($pfns.Count -eq 0) {
        $pfns.Add("${Id}_8wekyb3d8bbwe")
    }

    $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned'
    foreach ($pfn in @($pfns | Select-Object -Unique)) {
        New-Item -Path (Join-Path $root $pfn) -Force | Out-Null
    }

    Write-Output "removed $Id"
}

Invoke-OneDriveUninstall
foreach ($id in @(
        'Microsoft.BingNews'
        'Microsoft.BingWeather'
        'Microsoft.GetHelp'
        'Microsoft.Getstarted'
        'Microsoft.MicrosoftOfficeHub'
        'Microsoft.MicrosoftSolitaireCollection'
        'Microsoft.People'
        'Microsoft.PowerAutomateDesktop'
        'Microsoft.Todos'
        'Microsoft.WindowsFeedbackHub'
        'Microsoft.WindowsMaps'
        'Microsoft.ZuneMusic'
        'Microsoft.ZuneVideo'
        'MicrosoftCorporationII.QuickAssist'
        'Microsoft.Copilot'
        'Microsoft.GamingApp'
        'Microsoft.Xbox.TCUI'
        'Microsoft.XboxGamingOverlay'
        'Microsoft.XboxSpeechToTextOverlay'
    )) {
    Remove-Sl7App -Id $id
}

Write-Output 'Registry, OneDrive, and inbox apps applied. Sign out and back in.'

