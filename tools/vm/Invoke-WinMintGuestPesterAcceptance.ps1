#Requires -Version 7.6
<#
.SYNOPSIS
    Run Hyper-V guest acceptance Pester checks via PowerShell Direct.
#>
[CmdletBinding()]
param(
    [string]$VMName = 'WinMint-ARM-Test',
    [string]$GuestUser = 'dev',
    [string]$GuestPassword = 'winmint',
    [ValidateSet('Smoke', 'Full')]
    [string]$AcceptanceTier = 'Full',
    [string[]]$WslDistros = @()
)

$ErrorActionPreference = 'Stop'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run this in an elevated PowerShell session.' }

$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) { throw "VM '$VMName' not found." }
if ($vm.State -ne 'Running') { throw "VM '$VMName' is not running (state: $($vm.State))." }

$cred = [pscredential]::new($GuestUser, (ConvertTo-SecureString $GuestPassword -AsPlainText -Force))
$guestSignals = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    $terminalSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    $terminal = if (Test-Path -LiteralPath $terminalSettings) { Get-Content -LiteralPath $terminalSettings -Raw | ConvertFrom-Json } else { $null }
    $nixProfile = $null
    $ubuntuProfile = $null
    if ($terminal) {
        $nixProfile = @($terminal.profiles.list | Where-Object { [string]$_.name -eq 'NixOS' } | Select-Object -First 1)
        $ubuntuProfile = @($terminal.profiles.list | Where-Object { [string]$_.name -eq 'Ubuntu' } | Select-Object -First 1)
    }
    [pscustomobject]@{
        TerminalProfiles = if ($terminal) { @($terminal.profiles.list | ForEach-Object { [string]$_.name }) } else { @() }
        UbuntuProfileIcon = if ($ubuntuProfile) { [string]$ubuntuProfile.icon } else { $null }
        UbuntuProfileExists = [bool]$ubuntuProfile
        UbuntuIconExists = if ($ubuntuProfile -and $ubuntuProfile.icon) { Test-Path -LiteralPath ([string]$ubuntuProfile.icon) } else { $false }
        NixProfileIcon = if ($nixProfile) { [string]$nixProfile.icon } else { $null }
        NixProfileExists = [bool]$nixProfile
        NixIconExists = if ($nixProfile -and $nixProfile.icon) { Test-Path -LiteralPath ([string]$nixProfile.icon) } else { $false }
        CursorScheme = ((Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Cursors' -ErrorAction SilentlyContinue).'(default)')
        AccountPictureBmp = 'C:\ProgramData\Microsoft\User Account Pictures\user.bmp'
        AccountPictureBmpExists = Test-Path -LiteralPath 'C:\ProgramData\Microsoft\User Account Pictures\user.bmp'
        StartPins = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Name ConfigureStartPins -ErrorAction SilentlyContinue).ConfigureStartPins
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$testPath = Join-Path $repoRoot 'tests\acceptance\guest\HyperV-Guest.Tests.ps1'
if (-not (Test-Path -LiteralPath $testPath)) { throw "Guest acceptance tests not found: $testPath" }

Import-Module Pester -MinimumVersion 5.5.0 -ErrorAction Stop
$pesterConfig = New-PesterConfiguration
$pesterConfig.Run.Path = $testPath
$pesterConfig.Run.PassThru = $true
$pesterConfig.Data.Data = @{
    GuestSignals = $guestSignals
    Tier = $AcceptanceTier
    WslDistros = $WslDistros
}
$pesterResult = Invoke-Pester -Configuration $pesterConfig

$inspect = [ordered]@{
    TerminalProfiles = @($guestSignals.TerminalProfiles)
    UbuntuProfileIcon = [string]$guestSignals.UbuntuProfileIcon
    UbuntuProfileExists = [bool]$guestSignals.UbuntuProfileExists
    UbuntuIconExists = [bool]$guestSignals.UbuntuIconExists
    NixProfileIcon = [string]$guestSignals.NixProfileIcon
    NixProfileExists = [bool]$guestSignals.NixProfileExists
    NixIconExists = [bool]$guestSignals.NixIconExists
    CursorScheme = [string]$guestSignals.CursorScheme
    AccountPictureBmp = [string]$guestSignals.AccountPictureBmp
    AccountPictureBmpExists = [bool]$guestSignals.AccountPictureBmpExists
    StartPins = [string]$guestSignals.StartPins
    pesterPassed = ($pesterResult.FailedCount -eq 0)
    pesterFailed = @($pesterResult.Tests | Where-Object { $_.Result -eq 'Failed' } | ForEach-Object { $_.Name })
}

[ordered]@{
    inspect = $inspect
    pester = [ordered]@{
        passed = ($pesterResult.FailedCount -eq 0)
        total = $pesterResult.TotalCount
        failed = $pesterResult.FailedCount
        failures = @($pesterResult.Tests | Where-Object { $_.Result -eq 'Failed' } | ForEach-Object { $_.Name })
    }
} | ConvertTo-Json -Depth 6

if ($pesterResult.FailedCount -gt 0) { exit 1 }
