#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Remove the WinMint inbox app strip and stamp Deprovisioned marks.
.DESCRIPTION
  Windows PowerShell 5.1 and PowerShell 7. Run elevated.
  Under PowerShell 7, AppX cmdlets load through the Windows PowerShell compatibility session.
  -DryRun reports each app and removes nothing.
#>
param([switch] $DryRun)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# PowerShell 7 can promote native-command failures into errors. Keep 5.1 behavior.
if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
    $PSNativeCommandUseErrorActionPreference = $false
}


if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Output 'AppX cmdlets via Windows PowerShell 5.1 compatibility.'
    Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue
}
else {
    Import-Module Appx
}
Import-Module Dism

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


if (-not $DryRun) {
    $installedApps = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    $provisionedApps = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
    foreach ($id in $inboxIds) {
        Remove-InboxApp -Id $id -Installed $installedApps -Provisioned $provisionedApps
    }

    Write-Output 'Inbox apps applied. Sign out and back in.'
    return
}

Write-Output 'dry-run: inbox strip. Nothing will be removed.'
$installedApps = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
$provisionedApps = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
foreach ($id in $inboxIds) {
    $present = $false
    foreach ($pkg in @($installedApps)) {
        $name = [string] $pkg.Name
        if ($preserveIds -contains $name) { continue }
        $hit = (Test-CatalogIdMatch -Value $name -Id $id) -or
            (Test-CatalogIdMatch -Value ([string] $pkg.PackageFamilyName) -Id $id) -or
            (Test-CatalogIdMatch -Value ([string] $pkg.PackageFullName) -Id $id)
        if ($hit) { $present = $true }
    }

    foreach ($pkg in @($provisionedApps)) {
        $display = [string] $pkg.DisplayName
        if ($preserveIds -contains $display) { continue }
        $hit = (Test-CatalogIdMatch -Value $display -Id $id) -or (Test-CatalogIdMatch -Value ([string] $pkg.PackageName) -Id $id)
        if ($hit) { $present = $true }
    }

    if ($present) {
        Write-Output "dry-run: remove $id"
    }
    else {
        Write-Output "dry-run: absent $id"
    }
}

Write-Output 'dry-run: Deprovisioned marks would be written. Inbox apps not removed.'

