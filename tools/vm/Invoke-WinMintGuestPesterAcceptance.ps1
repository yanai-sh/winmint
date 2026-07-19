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
    $fedoraProfile = $null
    if ($terminal) {
        $nixProfile = @($terminal.profiles.list | Where-Object { [string]$_.name -eq 'NixOS' } | Select-Object -First 1)
        $ubuntuProfile = @($terminal.profiles.list | Where-Object { [string]$_.name -eq 'Ubuntu' } | Select-Object -First 1)
        $fedoraProfile = @($terminal.profiles.list | Where-Object { [string]$_.name -eq 'Fedora' } | Select-Object -First 1)
    }
    $shellPinsPath = Join-Path $env:ProgramData 'WinMint\Logs\FirstLogon_ShellPins.json'
    $shellPins = if (Test-Path -LiteralPath $shellPinsPath -PathType Leaf) {
        Get-Content -LiteralPath $shellPinsPath -Raw | ConvertFrom-Json
    }
    else { $null }
    $firstLogonLogPath = Join-Path $env:ProgramData 'WinMint\Logs\FirstLogon.log'
    $firstLogonLog = if (Test-Path -LiteralPath $firstLogonLogPath -PathType Leaf) {
        Get-Content -LiteralPath $firstLogonLogPath -Raw -ErrorAction SilentlyContinue
    }
    else { '' }
    $taskbarLayoutPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Shell\LayoutModification.xml'
    [pscustomobject]@{
        TerminalProfiles = if ($terminal) { @($terminal.profiles.list | ForEach-Object { [string]$_.name }) } else { @() }
        TerminalLaunchMode = if ($terminal) { [string]$terminal.launchMode } else { $null }
        TerminalCenterOnLaunch = if ($terminal) { [bool]$terminal.centerOnLaunch } else { $false }
        TerminalOpacity = if ($terminal -and $terminal.profiles.defaults) { [int]$terminal.profiles.defaults.opacity } else { -1 }
        TerminalColorScheme = if ($terminal -and $terminal.profiles.defaults) { [string]$terminal.profiles.defaults.colorScheme } else { $null }
        UbuntuProfileIcon = if ($ubuntuProfile) { [string]$ubuntuProfile.icon } else { $null }
        UbuntuProfileExists = [bool]$ubuntuProfile
        UbuntuIconExists = if ($ubuntuProfile -and $ubuntuProfile.icon -and ([string]$ubuntuProfile.icon -notmatch '^ms-appx:')) {
            Test-Path -LiteralPath ([string]$ubuntuProfile.icon)
        }
        else { $false }
        NixProfileIcon = if ($nixProfile) { [string]$nixProfile.icon } else { $null }
        NixProfileExists = [bool]$nixProfile
        NixIconExists = if ($nixProfile -and $nixProfile.icon -and ([string]$nixProfile.icon -notmatch '^ms-appx:')) {
            Test-Path -LiteralPath ([string]$nixProfile.icon)
        }
        else { $false }
        FedoraProfileExists = [bool]$fedoraProfile
        FedoraProfileIcon = if ($fedoraProfile) { [string]$fedoraProfile.icon } else { $null }
        CursorScheme = ((Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Cursors' -ErrorAction SilentlyContinue).'(default)')
        AccountPictureBmp = 'C:\ProgramData\Microsoft\User Account Pictures\user.bmp'
        AccountPictureBmpExists = Test-Path -LiteralPath 'C:\ProgramData\Microsoft\User Account Pictures\user.bmp'
        StartPins = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Name ConfigureStartPins -ErrorAction SilentlyContinue).ConfigureStartPins
        ShellPinsReportPresent = [bool]$shellPins
        ShellPinsStartAppIds = if ($shellPins) { @($shellPins.startAppIds) } else { @() }
        ShellPinsTaskbarAppIds = if ($shellPins) { @($shellPins.taskbarAppIds) } else { @() }
        TerminalProfileMockLogged = [bool]($firstLogonLog -match 'terminalProfile=mock')
        TaskbarLayoutPresent = Test-Path -LiteralPath $taskbarLayoutPath -PathType Leaf
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$testPath = Join-Path $repoRoot 'tests\acceptance\guest\HyperV-Guest.Tests.ps1'
if (-not (Test-Path -LiteralPath $testPath)) { throw "Guest acceptance tests not found: $testPath" }

Import-Module Pester -MinimumVersion 5.5.0 -ErrorAction Stop
$pesterConfig = New-PesterConfiguration
$pesterConfig.Run.PassThru = $true
$pesterConfig.Output.Verbosity = 'None'
$pesterConfig.Run.Container = New-PesterContainer -Path $testPath -Data @{
    TestData = @{
        GuestSignals = $guestSignals
        Tier = $AcceptanceTier
        WslDistros = $WslDistros
    }
}
$pesterResult = Invoke-Pester -Configuration $pesterConfig

$inspect = [ordered]@{
    TerminalProfiles = @($guestSignals.TerminalProfiles)
    TerminalLaunchMode = [string]$guestSignals.TerminalLaunchMode
    TerminalCenterOnLaunch = [bool]$guestSignals.TerminalCenterOnLaunch
    TerminalOpacity = [int]$guestSignals.TerminalOpacity
    TerminalColorScheme = [string]$guestSignals.TerminalColorScheme
    UbuntuProfileIcon = [string]$guestSignals.UbuntuProfileIcon
    UbuntuProfileExists = [bool]$guestSignals.UbuntuProfileExists
    UbuntuIconExists = [bool]$guestSignals.UbuntuIconExists
    NixProfileIcon = [string]$guestSignals.NixProfileIcon
    NixProfileExists = [bool]$guestSignals.NixProfileExists
    NixIconExists = [bool]$guestSignals.NixIconExists
    FedoraProfileExists = [bool]$guestSignals.FedoraProfileExists
    FedoraProfileIcon = [string]$guestSignals.FedoraProfileIcon
    CursorScheme = [string]$guestSignals.CursorScheme
    AccountPictureBmp = [string]$guestSignals.AccountPictureBmp
    AccountPictureBmpExists = [bool]$guestSignals.AccountPictureBmpExists
    StartPins = [string]$guestSignals.StartPins
    ShellPinsReportPresent = [bool]$guestSignals.ShellPinsReportPresent
    ShellPinsStartAppIds = @($guestSignals.ShellPinsStartAppIds)
    ShellPinsTaskbarAppIds = @($guestSignals.ShellPinsTaskbarAppIds)
    TerminalProfileMockLogged = [bool]$guestSignals.TerminalProfileMockLogged
    TaskbarLayoutPresent = [bool]$guestSignals.TaskbarLayoutPresent
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
