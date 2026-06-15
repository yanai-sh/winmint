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
. (Join-Path $RepositoryRoot 'src\runtime\image\Core.ps1')
$engine = Get-WinMintPath -Name RuntimeImageEntry
. $engine
Initialize-WinMintEngine -RepositoryRoot $RepositoryRoot

$null = Save-WinMintBuildProfileFromUiIntent `
    -RepositoryRoot $RepositoryRoot `
    -SettingsPath $SettingsPath `
    -OutputPath $OutputPath `
    -IncludeSecrets:$IncludeSecrets
