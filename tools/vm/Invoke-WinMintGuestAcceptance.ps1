#Requires -Version 7.6
<#
.SYNOPSIS
    Inspect a running WinMint Hyper-V guest and report the live desktop / Terminal
    acceptance signals.

.DESCRIPTION
    Uses PowerShell Direct to inspect the guest after first logon. This is a read-only
    check intended to confirm the exact Windows Terminal profile names, the Ubuntu/NixOS icon
    path, cursor state, account picture, installed apps, and Start pins.

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Invoke-WinMintGuestAcceptance.ps1 -VMName WinMint-ARM-Test
#>
[CmdletBinding()]
param(
    [string]$VMName = 'WinMint-ARM-Test',
    [string]$GuestUser = 'dev',
    [string]$GuestPassword = 'winmint'
)

$ErrorActionPreference = 'Stop'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run this in an elevated PowerShell - Hyper-V PowerShell Direct requires Administrator.' }

$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) { throw "VM '$VMName' not found." }
if ($vm.State -ne 'Running') { throw "VM '$VMName' is not running (state: $($vm.State))." }

$cred = [pscredential]::new($GuestUser, (ConvertTo-SecureString $GuestPassword -AsPlainText -Force))
Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
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
} | ConvertTo-Json -Depth 6

