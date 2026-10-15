#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Turn off consumer features and suggestion content.
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

. (Join-Path $PSScriptRoot 'Registry.ps1')

$pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
Set-RegDword $pol 'DisableWindowsConsumerFeatures' 1
Set-RegDword $pol 'DisableSoftLanding' 1

$cv = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
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
    Set-RegDword $cv $name 0
}

if ($DryRun) {
    Write-Output 'dry-run: consumer features not written.'
}
else {
    Write-Output 'Consumer features off. Sign out and back in.'
}
