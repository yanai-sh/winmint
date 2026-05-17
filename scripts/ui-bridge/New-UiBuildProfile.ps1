#Requires -Version 7.3
<#
.SYNOPSIS
  Builds a WinWS BuildProfile JSON file from UI settings JSON.
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

$engine = Join-Path $RepositoryRoot 'src\WinWS\WinWS.ps1'
. $engine
Initialize-WinWSEngine -RepositoryRoot $RepositoryRoot

$settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
$profile = New-WinWSBuildProfile -Settings $settings -IncludeSecrets:$IncludeSecrets
$null = Save-WinWSBuildProfile -BuildProfile $profile -Path $OutputPath
