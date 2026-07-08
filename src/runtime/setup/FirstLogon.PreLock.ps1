#Requires -Version 7.6
# Runs from autounattend FirstLogonCommands before FirstLogon.ps1 — earliest user-session guard.
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'ProvisioningGuard.ps1')
Enable-WinMintProvisioningGuard
Invoke-WinMintProvisioningDismissStartMenu
