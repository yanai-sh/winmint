#Requires -Version 7.3
<#
.SYNOPSIS
  Runs the WinWS engine build from an on-disk BuildProfile.json.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$ProfilePath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$engine = Join-Path $RepositoryRoot 'src\WinWS\WinWS.ps1'
. $engine
Initialize-WinWSEngine -RepositoryRoot $RepositoryRoot -DryRun:$DryRun

$buildProfile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
$null = Start-WinWSBuild -BuildProfile $buildProfile -DryRun:$DryRun
