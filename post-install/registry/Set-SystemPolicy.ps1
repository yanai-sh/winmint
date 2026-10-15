#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Activity history, update peering, companion apps, WPBT, Store notify, long paths, Developer Mode, sudo, and XDG directories.
.DESCRIPTION
  Maintainer working tree. Not ready for anyone else to run.
  Windows PowerShell 5.1 and PowerShell 7. Run elevated.
  This file stands alone. The working directory does not matter. A second run writes the same values.
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
