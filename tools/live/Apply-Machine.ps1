#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Curated WinMint machine registry for a live Windows install.
.DESCRIPTION
  Run from an elevated Windows PowerShell after Windows Update.
  Leaves UAC prompts on. Does not install the ISO or touch boot files.
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
Set-RegString 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Allow'

# SL7 settle target: Israel, en-US. Ireland is only the setup-time DMA latch and is not applied here.
Set-WinHomeLocation -GeoId 117
& "$env:SystemRoot\System32\tzutil.exe" /s 'Israel Standard Time'
Set-Culture -CultureInfo en-US

$dism = Start-Process -FilePath "$env:SystemRoot\System32\dism.exe" -ArgumentList '/Online','/Set-ReservedStorageState','/State:Disabled' -Wait -PassThru -WindowStyle Hidden
if ($dism.ExitCode -ne 0) {
    Write-Output "Reserved Storage left unchanged (dism exit $($dism.ExitCode))."
}

Write-Output 'Machine posture applied. Run Apply-User.ps1 for this account, then sign out.'
