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
