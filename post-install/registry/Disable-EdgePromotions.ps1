#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Turn off Edge promotions, shopping, and first-run. Leaves Edge installed.
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

$regExe = Join-Path $PSScriptRoot 'Set-RegExeValue.ps1'

$edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
& $regExe -Path 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' -Name 'CreateDesktopShortcutDefault' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path $edge -Name 'PersonalizationReportingEnabled' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path "$edge\ExtensionInstallBlocklist" -Name '1' -Type 'REG_SZ' -Data 'ofefcgjbeghpigppfmkologfjadafddi' -DryRun:$DryRun
& $regExe -Path $edge -Name 'ShowRecommendationsEnabled' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path $edge -Name 'HideFirstRunExperience' -Type 'REG_DWORD' -Data '1' -DryRun:$DryRun
& $regExe -Path $edge -Name 'NewTabPageLocation' -Type 'REG_SZ' -Data 'about:blank' -DryRun:$DryRun
& $regExe -Path $edge -Name 'UserFeedbackAllowed' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path $edge -Name 'ConfigureDoNotTrack' -Type 'REG_DWORD' -Data '1' -DryRun:$DryRun
& $regExe -Path $edge -Name 'AlternateErrorPagesEnabled' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path $edge -Name 'EdgeCollectionsEnabled' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path $edge -Name 'EdgeShoppingAssistantEnabled' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path $edge -Name 'MicrosoftEdgeInsiderPromotionEnabled' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path $edge -Name 'ShowMicrosoftRewards' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path $edge -Name 'WebWidgetAllowed' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path $edge -Name 'DiagnosticData' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path $edge -Name 'EdgeAssetDeliveryServiceEnabled' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path $edge -Name 'WalletDonationEnabled' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun
& $regExe -Path $edge -Name 'DefaultBrowserSettingsCampaignEnabled' -Type 'REG_DWORD' -Data '0' -DryRun:$DryRun

if ($DryRun) {
    Write-Output 'dry-run: Edge promotions not written.'
}
else {
    Write-Output 'Edge promotions off.'
}
