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

function Test-WinMintGuiAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-WinMintGuiQuotedArgument {
    param([Parameter(Mandatory)][string]$Value)

    '"' + ($Value -replace '"', '\"') + '"'
}

if (-not (Test-WinMintGuiAdministrator)) {
    $forwardArgs = [System.Collections.Generic.List[string]]::new()
    $forwardArgs.Add('-NoProfile')
    $forwardArgs.Add('-ExecutionPolicy')
    $forwardArgs.Add('Bypass')
    $forwardArgs.Add('-File')
    $forwardArgs.Add($PSCommandPath)
    if ($SystemTitlebar) { $forwardArgs.Add('-SystemTitlebar') }
    if ($CustomTitlebar) { $forwardArgs.Add('-CustomTitlebar') }
    foreach ($arg in @($AppArgs | Where-Object { $_ -ne '--' })) {
        $forwardArgs.Add($arg)
    }

    $elevated = Start-Process `
        -FilePath (Get-Process -Id $PID).Path `
        -ArgumentList (($forwardArgs | ForEach-Object { ConvertTo-WinMintGuiQuotedArgument -Value ([string]$_) }) -join ' ') `
        -Verb RunAs `
        -WindowStyle Minimized `
        -Wait `
        -PassThru
    exit $elevated.ExitCode
}

. "$PSScriptRoot\src\runtime\image\Core.ps1"

$binary = Get-WinMintPath -Name GuiBinary
$guiManifest = Get-WinMintPath -Name GuiCargoToml
$sourceLauncher = Get-WinMintPath -Name GuiToolsRoot -ChildPath 'Start-GuiDev.ps1'
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
