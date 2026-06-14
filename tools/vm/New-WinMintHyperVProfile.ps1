#Requires -Version 7.3
<#
.SYNOPSIS
    Author a Hyper-V-ready WinMint build profile.

.DESCRIPTION
    Wraps the normal WinMint profile authoring flow with a Hyper-V-specific
    contract: Windows 11 Pro, the Pro generic key, and a fully unattended local
    account. That keeps the VM path honest and prevents accidental Home builds
    from slipping into the Hyper-V test loop.

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\New-WinMintHyperVProfile.ps1 -OutPath .\output\hyper-v.json -SourceIso .\tests\fixtures\iso\official-win11-25h2-english-arm64-v2.iso
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutPath,
    [Parameter(Mandatory)][string]$SourceIso,
    [string]$ComputerName = 'WinMintVM',
    [string]$AccountName = 'dev',
    [string]$Password = 'winmint',
    [string[]]$Install = @('nilesoft'),
    [string[]]$Browser = @('zen-browser', 'helium'),
    [string[]]$Editor = @('cursor', 'neovim'),
    [string[]]$Wsl2Distros = @('Ubuntu', 'NixOS-WSL'),
    [switch]$KeepEdge,
    [switch]$KeepGaming,
    [switch]$KeepCopilot,
    [switch]$NoAutoLogon,
    [switch]$AllowElevate
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$cli = Join-Path $repoRoot 'WinMint-CLI.ps1'
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source

if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) {
    throw "WinMint CLI not found: $cli"
}

$cliArguments = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $cli,
    'new',
    $OutPath,
    '-Edition', 'Pro',
    '-GenericKey', 'On',
    '-ComputerName', $ComputerName,
    '-AccountName', $AccountName,
    '-AccountMode', 'Local',
    '-Password', $Password
)

if ($SourceIso) { $cliArguments += @('-SourceIso', $SourceIso) }
if (-not $NoAutoLogon) { $cliArguments += '-AutoLogon' }
if ($KeepEdge) { $cliArguments += '-KeepEdge' }
if ($KeepGaming) { $cliArguments += '-KeepGaming' }
if ($KeepCopilot) { $cliArguments += '-KeepCopilot' }
if ($Install.Count -gt 0) {
    $cliArguments += @('-Install', ($Install -join ','))
}
if ($Browser.Count -gt 0) {
    $cliArguments += @('-Browser', ($Browser -join ','))
}
if ($Editor.Count -gt 0) {
    $cliArguments += @('-Editor', ($Editor -join ','))
}
if ($Wsl2Distros.Count -gt 0) {
    $cliArguments += @('-Wsl2Distros', ($Wsl2Distros -join ','))
}
if ($AllowElevate) { $cliArguments += '-AllowElevate' }

& $pwsh @cliArguments
if ($LASTEXITCODE -ne 0) {
    throw "Hyper-V profile authoring failed with exit code $LASTEXITCODE."
}

$profile = Get-Content -LiteralPath $OutPath -Raw | ConvertFrom-Json
$profile.profileName = 'Hyper-V Test'
$profile | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $OutPath -Encoding UTF8

& $pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Test-WinMintHyperVProfile.ps1') -ProfilePath $OutPath
if ($LASTEXITCODE -ne 0) {
    throw "Hyper-V profile validation failed with exit code $LASTEXITCODE."
}

Write-Host "Hyper-V profile written: $OutPath"
