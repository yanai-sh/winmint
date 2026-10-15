#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Curated WinMint registry, a OneDrive purge, and the product inbox-app strip.
.DESCRIPTION
  Elevated Windows PowerShell, after Windows Update. Sign out afterward.
  Leaves UAC, Reserved Storage, language, home region, and time zone alone.
  Does not remove Windows capabilities or optional features.
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

function Stop-OneDriveProcess {
    $procs = @(Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessName -eq 'OneDrive' -or $_.ProcessName -eq 'OneDriveSetup' })
    if ($procs.Count -eq 0) {
        return
    }

    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Clear-OneDriveRunKey {
    param([Parameter(Mandatory)][string] $KeyPath)
    $query = & reg.exe query $KeyPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        return
    }

    foreach ($line in @($query)) {
        if ($line -notmatch '^\s+(\S+)\s+REG_\w+\s+(.*)$') {
            continue
        }

        $name = $Matches[1]
        $data = $Matches[2]
        if ($name -like '*OneDrive*' -or $data -like '*OneDrive*') {
            & reg.exe delete $KeyPath /v $name /f | Out-Null
            Write-Output "cleared $KeyPath\$name"
        }
    }
}

function Remove-OneDriveTree {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Path) {
        Write-Output "still present: $Path"
    }
    else {
        Write-Output "deleted $Path"
    }
}

function Remove-TrustedInstallerFile {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    & takeown.exe /F $Path /A | Out-Null
    & icacls.exe $Path /grant '*S-1-5-32-544:F' | Out-Null
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Write-Output "OneDrive setup still present: $Path"
    }
    else {
        Write-Output "deleted $Path"
    }
}

function Invoke-OneDrivePurge {
    Stop-OneDriveProcess

    $setups = [System.Collections.Generic.List[string]]::new()
    foreach ($setup in @(
            (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe')
            (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe')
        )) {
        if (Test-Path -LiteralPath $setup -PathType Leaf) {
            $setups.Add($setup)
        }
    }

    $usersRoot = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $usersRoot) {
        foreach ($userDir in @(Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue)) {
            if ($userDir.Name -in @('Public', 'Default', 'Default User', 'All Users')) {
                continue
            }

            $userSetup = Join-Path $userDir.FullName 'AppData\Local\Microsoft\OneDrive'
            if (Test-Path -LiteralPath $userSetup) {
                foreach ($found in @(Get-ChildItem -LiteralPath $userSetup -Filter 'OneDriveSetup.exe' -Recurse -File -ErrorAction SilentlyContinue)) {
                    $setups.Add($found.FullName)
                }
            }
        }
    }

    $ran = $false
    foreach ($setup in @($setups | Select-Object -Unique)) {
        $ran = $true
        $proc = Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait -PassThru -WindowStyle Hidden
        Write-Output "OneDriveSetup exit $($proc.ExitCode): $setup"
    }

    if (-not $ran) {
        Write-Output 'OneDriveSetup.exe is not on this PC.'
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        & $winget.Source uninstall --id Microsoft.OneDrive --exact --accept-source-agreements --disable-interactivity
        Write-Output "winget OneDrive exit $LASTEXITCODE"
    }

    Stop-OneDriveProcess

    try {
        Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -like '*OneDrive*' } |
            ForEach-Object {
                Unregister-ScheduledTask -InputObject $_ -Confirm:$false -ErrorAction SilentlyContinue
                Write-Output "removed task $($_.TaskName)"
            }
    }
    catch {
        Write-Output "scheduled task cleanup skipped: $($_.Exception.Message)"
    }

    foreach ($run in @(
            'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
            'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
            'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'
        )) {
        Clear-OneDriveRunKey -KeyPath $run
    }

    $defaultHive = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT'
    $loadedDefault = $false
    try {
        if (Test-Path -LiteralPath $defaultHive -PathType Leaf) {
            & reg.exe load HKU\WinMintDefault $defaultHive | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $loadedDefault = $true
                Clear-OneDriveRunKey -KeyPath 'HKU\WinMintDefault\Software\Microsoft\Windows\CurrentVersion\Run'
                Clear-OneDriveRunKey -KeyPath 'HKU\WinMintDefault\Software\Microsoft\Windows\CurrentVersion\RunOnce'
            }
        }
    }
    finally {
        if ($loadedDefault) {
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            & reg.exe unload HKU\WinMintDefault | Out-Null
        }
    }

    foreach ($setup in @(
            (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe')
            (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe')
        )) {
        Remove-TrustedInstallerFile -Path $setup
    }

    $clientDirs = [System.Collections.Generic.List[string]]::new()
    $clientDirs.Add((Join-Path $env:ProgramData 'Microsoft OneDrive'))
    $clientDirs.Add((Join-Path $env:ProgramData 'Microsoft\OneDrive'))
    $programFiles = $env:ProgramFiles
    if ($programFiles) {
        $clientDirs.Add((Join-Path $programFiles 'Microsoft OneDrive'))
    }

    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($programFilesX86) {
        $clientDirs.Add((Join-Path $programFilesX86 'Microsoft OneDrive'))
    }

    if (Test-Path -LiteralPath $usersRoot) {
        foreach ($userDir in @(Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue)) {
            if ($userDir.Name -in @('Public', 'Default', 'Default User', 'All Users')) {
                continue
            }

            $clientDirs.Add((Join-Path $userDir.FullName 'AppData\Local\Microsoft\OneDrive'))
        }
    }

    foreach ($dir in @($clientDirs | Select-Object -Unique)) {
        Remove-OneDriveTree -Path $dir
    }

    $shortcutRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($root in @(
            [Environment]::GetFolderPath('Desktop')
            [Environment]::GetFolderPath('CommonDesktopDirectory')
            (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu')
            (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu')
            (Join-Path $env:SystemDrive 'Users\Default\Desktop')
            (Join-Path $env:SystemDrive 'Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu')
        )) {
        if ($root) {
            $shortcutRoots.Add($root)
        }
    }

    foreach ($root in @($shortcutRoots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        foreach ($lnk in @(Get-ChildItem -LiteralPath $root -Filter 'OneDrive.lnk' -Recurse -File -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $lnk.FullName -Force -ErrorAction SilentlyContinue
            Write-Output "deleted $($lnk.FullName)"
        }
    }

    $namespace = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
    if (Test-Path -LiteralPath $namespace) {
        Remove-Item -LiteralPath $namespace -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output 'removed OneDrive navigation-pane entry'
    }

    $clientState = 'HKCU:\Software\Microsoft\OneDrive'
    if (Test-Path -LiteralPath $clientState) {
        Remove-Item -LiteralPath $clientState -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output 'removed HKCU OneDrive client state'
    }

    $syncFolder = Join-Path $env:USERPROFILE 'OneDrive'
    if (Test-Path -LiteralPath $syncFolder) {
        Write-Output "left user folder: $syncFolder"
    }
}

function Test-CatalogIdMatch {
    param([AllowEmptyString()][string] $Value, [Parameter(Mandatory)][string] $Id)
    if ([string]::IsNullOrEmpty($Value)) {
        return $false
    }

    if ($Value -eq $Id) { return $true }
    if ($Value.StartsWith($Id + '_', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($Value.StartsWith($Id + '.', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($Value.IndexOf('.' + $Id + '_', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    if ($Value.EndsWith('.' + $Id, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $false
}

function Get-FallbackFamilyName {
    param([Parameter(Mandatory)][string] $Id)
    switch ($Id) {
        'Clipchamp.Clipchamp' { return 'Clipchamp.Clipchamp_yxz26nhyzhsrt' }
        '5319275A.WhatsAppDesktop' { return '5319275A.WhatsAppDesktop_cv1g1gvanyjgm' }
        default { return "${Id}_8wekyb3d8bbwe" }
    }
}

function Remove-InboxApp {
    param(
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)] $Installed,
        [Parameter(Mandatory)] $Provisioned
    )
    $pfns = New-Object System.Collections.Generic.List[string]
    $touched = $false
    foreach ($pkg in @($Installed)) {
        $name = [string] $pkg.Name
        if ($preserveIds -contains $name) {
            continue
        }

        $hit = (Test-CatalogIdMatch -Value $name -Id $Id) -or
            (Test-CatalogIdMatch -Value ([string] $pkg.PackageFamilyName) -Id $Id) -or
            (Test-CatalogIdMatch -Value ([string] $pkg.PackageFullName) -Id $Id)
        if (-not $hit) {
            continue
        }

        $touched = $true
        try {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
        }
        catch {
            Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
        }

        if ($pkg.PackageFamilyName) {
            $pfns.Add([string] $pkg.PackageFamilyName)
        }
    }

    foreach ($pkg in @($Provisioned)) {
        $display = [string] $pkg.DisplayName
        if ($preserveIds -contains $display) {
            continue
        }

        $packageName = [string] $pkg.PackageName
        $hit = (Test-CatalogIdMatch -Value $display -Id $Id) -or (Test-CatalogIdMatch -Value $packageName -Id $Id)
        if (-not $hit) {
            continue
        }

        $touched = $true
        Remove-AppxProvisionedPackage -Online -PackageName $packageName -ErrorAction SilentlyContinue | Out-Null
        $parts = $packageName -split '_'
        if ($parts.Count -ge 2 -and $display) {
            $pfns.Add(('{0}_{1}' -f $display, $parts[-1]))
        }
    }

    if ($pfns.Count -eq 0) {
        $pfns.Add((Get-FallbackFamilyName -Id $Id))
    }

    $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned'
    foreach ($pfn in @($pfns | Select-Object -Unique)) {
        New-Item -Path (Join-Path $root $pfn) -Force | Out-Null
    }

    if ($touched) {
        Write-Output "removed $Id"
    }
    else {
        Write-Output "absent $Id"
    }
}

# ProductPosture.PreserveAppx — never remove these, even on a prefix hit.
$preserveIds = @(
    'Microsoft.WindowsStore'
    'Microsoft.StorePurchaseApp'
    'Microsoft.DesktopAppInstaller'
    'Microsoft.SecHealthUI'
    'Microsoft.Edge'
    'Microsoft.EdgeWebView'
    'Microsoft.WebView2'
    'Microsoft.WindowsCamera'
    'Microsoft.WindowsAlarms'
    'Microsoft.WindowsNotepad'
    'Microsoft.ScreenSketch'
    'Microsoft.Windows.Photos'
    'Microsoft.Paint'
    'AD2F1837.HPSystemInformation'
    'AD2F1837.HPPrivacySettings'
    'AD2F1837.HPSupportAssistant'
    'DellInc.DellCommandUpdate'
    'DellInc.DellPowerManager'
    'E046963F.LenovoSettings'
    'E046963F.LenovoVantage'
    'Microsoft.Windows.PeopleExperienceHost'
    'Windows.CBSPreview'
    'Microsoft.XboxGameCallableUI'
    'Microsoft.Windows.ParentalControls'
    'MicrosoftWindows.Client.CBS'
)

# ProductPosture.AppxIds minus the two preserve overlaps above.
$inboxIds = @(
    'Microsoft.GetHelp'
    'Microsoft.MicrosoftOfficeHub'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.549981C3F5F10'
    'MicrosoftCorporationII.MicrosoftFamily'
    'Microsoft.StartExperiencesApp'
    'Microsoft.BingSearch'
    'Microsoft.BingFinance'
    'Microsoft.BingFoodAndDrink'
    'Microsoft.BingHealthAndFitness'
    'Microsoft.BingNews'
    'Microsoft.BingSports'
    'Microsoft.BingTranslator'
    'Microsoft.BingTravel'
    'Microsoft.BingWeather'
    'Microsoft.Getstarted'
    'Microsoft.MicrosoftPowerBIForWindows'
    'Microsoft.MixedReality.Portal'
    'Microsoft.NetworkSpeedTest'
    'Microsoft.Office.OneNote'
    'Microsoft.Office.Sway'
    'Microsoft.OutlookForWindows'
    'Microsoft.PowerAutomateDesktop'
    'Microsoft.RemoteDesktop'
    'Microsoft.RemoteDesktopPreview'
    'Microsoft.SkypeApp'
    'Microsoft.Todos'
    'Microsoft.Wallet'
    'Microsoft.Whiteboard'
    'Microsoft.Windows.AIHub'
    'Microsoft.Windows.DevHome'
    'Microsoft.WindowsMaps'
    'Microsoft.WindowsPhone'
    'Microsoft.WindowsReadingList'
    'MicrosoftWindows.Client.WebExperience'
    'Microsoft.Copilot'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.ZuneMusic'
    'Microsoft.ZuneVideo'
    'Clipchamp.Clipchamp'
    'Microsoft.WindowsCalculator'
    'MicrosoftCorporationII.QuickAssist'
    'Microsoft.WindowsSoundRecorder'
    'Microsoft.MicrosoftStickyNotes'
    'MSTeams'
    'MicrosoftTeams'
    'Microsoft.People'
    'Microsoft.windowscommunicationsapps'
    'Microsoft.Messaging'
    'Microsoft.OneConnect'
    'Microsoft.CommsPhone'
    'Microsoft.ConnectivityStore'
    'Microsoft.GamingApp'
    'Microsoft.XboxApp'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxIdentityProvider'
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.Xbox.TCUI'
    'Spotify'
    'SpotifyAB.SpotifyMusic'
    'TikTok'
    'BytedancePte.Ltd.TikTok'
    'Netflix'
    '4DF9E0F8.Netflix'
    'Disney'
    'DisneyMagicKingdoms'
    'A278AB0D.DisneyMagicKingdoms'
    'Amazon.com.Amazon'
    'AmazonVideo.PrimeVideo'
    'Facebook'
    'Facebook.Facebook'
    'Facebook.InstagramBeta'
    'Instagram'
    'LinkedInforWindows'
    'Twitter'
    'XING'
    'XINGAG.XING'
    'Flipboard'
    'HULULLC.HULUPLUS'
    'PicsArt'
    'Duolingo-LearnLanguagesforFree'
    'D5EA27B7.Duolingo-LearnLanguagesforFree'
    'king.com'
    'HiddenCity'
    'FarmVille2CountryEscape'
    'MarchofEmpires'
    'Royal Revolt'
    'KeeperSecurityInc.Keeper'
    'WinZipComputing.WinZipUniversal'
    'McAfee'
    'NortonLifeLock'
    'NortonSecurity'
    'ExpressVPN'
    'Surfshark'
    'SurfsharkVPN'
    'AVGTechnologies'
    'AvastSoftware'
    'KasperskyLab'
    'DolbyLaboratories'
    'Piriform.CCleaner'
    'AD2F1837.HPAIExperienceCenter'
    'AD2F1837.HPConnectedMusic'
    'AD2F1837.HPConnectedPhotopoweredbySnapfish'
    'AD2F1837.HPJumpStarts'
    'AD2F1837.HPRegistration'
    'AD2F1837.HPWelcome'
    'AD2F1837.HPWorkWell'
    'DellInc.DellDigitalDelivery'
    'DellInc.DellMobileConnect'
    'E046963F.LenovoCompanion'
    '5319275A.WhatsAppDesktop'
)

Invoke-OneDrivePurge
$installedApps = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
$provisionedApps = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
foreach ($id in $inboxIds) {
    Remove-InboxApp -Id $id -Installed $installedApps -Provisioned $provisionedApps
}

Write-Output 'Registry, OneDrive, and inbox apps applied. Sign out and back in.'

