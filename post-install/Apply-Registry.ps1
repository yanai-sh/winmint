#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Run each registry task script.
.DESCRIPTION
  Maintainer working tree. Not ready for anyone else to run.
  Windows PowerShell 5.1 and PowerShell 7. Run elevated, after Windows Update.
  Each task script lives in its own folder under registry\ and also runs on its own.
  Sign out afterward. Leaves UAC, Reserved Storage, language, home region, and time zone alone.
  -DryRun prints each value and writes nothing.
#>
param([switch] $DryRun)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
    $PSNativeCommandUseErrorActionPreference = $false
}

$registry = Join-Path $PSScriptRoot 'registry'
foreach ($name in @(
        'Set-QuietTaskbar\Set-QuietTaskbar.ps1'
        'Disable-ConsumerFeatures\Disable-ConsumerFeatures.ps1'
        'Set-StoreAutoDownload\Set-StoreAutoDownload.ps1'
        'Set-OneDrivePolicy\Set-OneDrivePolicy.ps1'
        'Disable-DeviceCompanionApps\Disable-DeviceCompanionApps.ps1'
        'Disable-ActivityHistory\Disable-ActivityHistory.ps1'
        'Disable-DeliveryOptimization\Disable-DeliveryOptimization.ps1'
        'Disable-EdgePromotions\Disable-EdgePromotions.ps1'
        'Enable-DeveloperMode\Enable-DeveloperMode.ps1'
        'Enable-Sudo\Enable-Sudo.ps1'
        'Enable-LongPaths\Enable-LongPaths.ps1'
        'Disable-Wpbt\Disable-Wpbt.ps1'
        'Set-ExplorerView\Set-ExplorerView.ps1'
        'Set-ShellFolders\Set-ShellFolders.ps1'
        'Set-XdgEnvironment\Set-XdgEnvironment.ps1'
    )) {
    $path = Join-Path $registry $name
    Write-Output "registry: $name"
    if ($DryRun) {
        & $path -DryRun
    }
    else {
        & $path
    }
}

if ($DryRun) {
    Write-Output 'dry-run: registry not written.'
}
else {
    Write-Output 'Registry applied. Sign out and back in.'
}
