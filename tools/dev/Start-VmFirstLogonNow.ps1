#Requires -Version 7.6
<#
.SYNOPSIS
    Launch FirstLogon on the VM when you are already at the dev desktop (no push/reboot).
#>
[CmdletBinding()]
param(
    [string]$VMName = 'WinMint-ARM-Test',
    [string]$GuestUser = 'dev',
    [string]$GuestPassword = 'winmint',
    [ValidateSet('Auto', 'Headless', 'Console')]
    [string]$AgentMode = 'Auto',
    [switch]$WaitForAgent,
    [int]$TimeoutMinutes = 60
)

$pushScript = Join-Path $PSScriptRoot '..\vm\Push-WinMintSetupScripts.ps1'
& $pushScript -VMName $VMName -GuestUser $GuestUser -GuestPassword $GuestPassword `
    -LaunchOnly -RerunFirstLogon -AgentMode $AgentMode -WaitForAgent:$WaitForAgent `
    -TimeoutMinutes $TimeoutMinutes
