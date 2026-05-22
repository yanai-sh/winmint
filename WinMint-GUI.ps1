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
$guiManifest = Get-WinMintPath -Name GuiCargoToml
$sourceLauncher = Get-WinMintPath -Name GuiTool -ChildPath 'Start-GuiDev.ps1'
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

if ((Test-Path -LiteralPath $guiManifest -PathType Leaf) -and
    (Test-Path -LiteralPath $sourceLauncher -PathType Leaf)) {
    $sourceArguments = [System.Collections.Generic.List[string]]::new()
    if ($SystemTitlebar) {
        $sourceArguments.Add('-SystemTitlebar')
    }
    elseif ($CustomTitlebar) {
        $sourceArguments.Add('-CustomTitlebar')
    }
    foreach ($arg in @($AppArgs | Where-Object { $_ -ne '--' })) {
        $sourceArguments.Add($arg)
    }

    & $sourceLauncher @($sourceArguments.ToArray())
    exit $LASTEXITCODE
}

if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
    throw "WinMint GUI executable was not found at '$binary'."
}

& $binary @($arguments.ToArray())
exit $LASTEXITCODE
