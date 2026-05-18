#Requires -Version 7.3
<#
.SYNOPSIS
  Builds a WinMint BuildProfile JSON file from UI settings JSON.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$SettingsPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [switch]$IncludeSecrets
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$script:WinMintRepositoryRoot = $RepositoryRoot
. (Join-Path $RepositoryRoot 'src\WinMint\Core.ps1')
$engine = Get-WinMintPath -Name EngineEntry
. $engine
Initialize-WinMintEngine -RepositoryRoot $RepositoryRoot

$settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
$profile = New-WinMintBuildProfileFromSettings -Settings $settings -IncludeSecrets:$IncludeSecrets
$null = Save-WinMintBuildProfile -BuildProfile $profile -Path $OutputPath
