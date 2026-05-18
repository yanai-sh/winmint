#Requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments = @()
)

$ErrorActionPreference = 'Stop'
Write-Warning 'WinMint-UI.ps1 is deprecated. Use WinMint-LegacyUI.ps1 for the legacy WPF UI or WinMint-GUI.ps1 for the primary GPUI.'

$legacy = Join-Path $PSScriptRoot 'WinMint-LegacyUI.ps1'
& $legacy @RemainingArguments
exit $LASTEXITCODE
