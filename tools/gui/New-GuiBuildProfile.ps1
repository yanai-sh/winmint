#Requires -Version 7.3
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$AllowElevate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:WinMintRepositoryRoot = $root
. (Join-Path $root 'src\runtime\image\Core.ps1')

$intentPath = Get-WinMintPath -Name OutputRoot -ChildPath 'gui\ui-intent.json'
$profilePath = Get-WinMintPath -Name OutputRoot -ChildPath 'gui\BuildProfile.json'

if (-not (Test-Path -LiteralPath $intentPath -PathType Leaf)) {
    throw "GUI intent was not found: $intentPath"
}

$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$bridge = Get-WinMintPath -Name UiBridgeToolsRoot -ChildPath 'New-UiBuildProfile.ps1'
$cli = Get-WinMintPath -Name RepoRoot -ChildPath 'WinMint-CLI.ps1'

& $pwsh -NoProfile -ExecutionPolicy Bypass -File $bridge `
    -RepositoryRoot $root `
    -SettingsPath $intentPath `
    -OutputPath $profilePath
if ($LASTEXITCODE -ne 0) {
    throw "Profile bridge failed with exit code $LASTEXITCODE."
}

Write-Host "Build profile: $profilePath"

if ($DryRun) {
    $cliArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cli, '-DryRun', '-ProfilePath', $profilePath)
    if ($AllowElevate) {
        $cliArguments += '-AllowElevate'
    }

    & $pwsh @cliArguments
    if ($LASTEXITCODE -ne 0) {
        throw "WinMint CLI dry run failed with exit code $LASTEXITCODE."
    }
}
