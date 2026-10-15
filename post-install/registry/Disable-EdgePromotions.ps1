#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Turn off Edge promotions, shopping, and first-run. Leaves Edge installed.
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


$edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'CreateDesktopShortcutDefault' 0
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

if ($DryRun) {
    Write-Output 'dry-run: Edge promotions not written.'
}
else {
    Write-Output 'Edge promotions off.'
}
