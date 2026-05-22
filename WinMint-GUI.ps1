#Requires -Version 7.3
[CmdletBinding()]
param(
    [switch]$SystemTitlebar,
    [switch]$CustomTitlebar,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AppArgs = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. "$PSScriptRoot\src\engine\Core.ps1"

$binary = Get-WinMintPath -Name GuiBinary
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
    throw "WinMint GPUI is not packaged at '$binary'. Build it with tools\release\Build-WinMintGui.ps1 or use WinMint-LegacyUI.ps1."
}

$arguments = [System.Collections.Generic.List[string]]::new()
if ($SystemTitlebar -and $CustomTitlebar) {
    throw 'Use either -SystemTitlebar or -CustomTitlebar, not both.'
}
if ($SystemTitlebar) {
    $arguments.Add('--system-titlebar')
}
foreach ($arg in @($AppArgs | Where-Object { $_ -ne '--' })) {
    $arguments.Add($arg)
}

& $binary @($arguments.ToArray())
exit $LASTEXITCODE
