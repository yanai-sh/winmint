#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Turn off consumer features and suggestion content.
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
    $output = & $reg add $regPath /v $Name /t $Type /d $Data /f 2>&1
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
