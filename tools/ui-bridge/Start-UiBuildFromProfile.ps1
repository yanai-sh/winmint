#Requires -Version 7.3
<#
.SYNOPSIS
  Runs the WinMint engine build from an on-disk BuildProfile.json.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$ProfilePath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$script:WinMintRepositoryRoot = $RepositoryRoot
. (Join-Path $RepositoryRoot 'src\engine\Core.ps1')
$engine = Get-WinMintPath -Name EngineEntry
. $engine
Initialize-WinMintEngine -RepositoryRoot $RepositoryRoot -DryRun:$DryRun

$buildProfile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
$null = Start-WinMintBuild -BuildProfile $buildProfile -DryRun:$DryRun
