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
. (Join-Path $root 'src\WinMint\Core.ps1')

$intentPath = Get-WinMintPath -Name Output -ChildPath 'gpui\ui-intent.json'
$profilePath = Get-WinMintPath -Name Output -ChildPath 'gpui\BuildProfile.json'

if (-not (Test-Path -LiteralPath $intentPath -PathType Leaf)) {
    throw "GPUI intent was not found: $intentPath"
}

$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$bridge = Get-WinMintPath -Name UiBridgeTool -ChildPath 'New-UiBuildProfile.ps1'
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
