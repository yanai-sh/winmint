#Requires -Version 7.6
<#
.SYNOPSIS
    Open password-free VMConnect Basic session to a running WinMint test VM.

.DESCRIPTION
    Uses host DisableEnhancedMode plus (on VM acceptance images) guest
    DisableEnhancedSessionConsoleConnection so you can watch Setup and FirstLogon
    without an Enhanced Session login prompt. Do not double-click the VM in
    Hyper-V Manager — that opens Enhanced Session and asks for dev/winmint.

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Start-WinMintVmObserve.ps1 -VMName WinMint-ARM-Test
#>
[CmdletBinding()]
param(
    [string]$VMName = 'WinMint-ARM-Test',
    [switch]$EnhancedSession
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WinMint-VmConsole.ps1')

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw 'Hyper-V VM observation requires an elevated PowerShell session.'
}

if ($EnhancedSession) {
    $result = Start-WinMintVmObserve -VMName $VMName -EnhancedSession
}
else {
    $vm = Get-VM -Name $VMName -ErrorAction Stop
    if ($vm.State -ne 'Running') {
        throw "VM '$VMName' is not running (state: $($vm.State))."
    }
    $proc = Open-WinMintVmConnectBasicWatch -VMName $VMName
    $result = [ordered]@{
        observeMode = 'basic'
        observePid = $proc.Id
        reused = $false
        refreshed = $true
    }
}
$result | ConvertTo-Json -Depth 3
