#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Activity history, update peering, companion apps, WPBT, Store notify, long paths, Developer Mode, sudo, and XDG directories.
.DESCRIPTION
  Maintainer working tree. Not ready for anyone else to run.
  Windows PowerShell 5.1 and PowerShell 7. Run elevated.
  Activity history is off. Clipboard history is left alone.
  Updates still download from Microsoft. This PC does not peer them.
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


$system = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
Set-RegDword $system 'EnableActivityFeed' 0
Set-RegDword $system 'PublishUserActivities' 0
Set-RegDword $system 'UploadUserActivities' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution' 1
Set-RegDword 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' 'AutoDownload' 2
Set-RegDword 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1
Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' 'AllowDevelopmentWithoutDevLicense' 1
Set-RegDword 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo' 'Enabled' 3
Set-RegExpand 'HKCU:\Environment' 'XDG_CONFIG_HOME' '%USERPROFILE%\.config'
Set-RegExpand 'HKCU:\Environment' 'XDG_DATA_HOME' '%USERPROFILE%\.local\share'
Set-RegExpand 'HKCU:\Environment' 'XDG_STATE_HOME' '%USERPROFILE%\.local\state'
Set-RegExpand 'HKCU:\Environment' 'XDG_CACHE_HOME' '%USERPROFILE%\.cache'

if ($DryRun) {
    Write-Output 'dry-run: system policy not written.'
}
else {
    Write-Output 'System policy applied. Sign out and back in.'
}
