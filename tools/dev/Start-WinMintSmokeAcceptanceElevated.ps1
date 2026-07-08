#Requires -Version 7.6
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Start managed Hyper-V smoke acceptance from an elevated shell (UAC-safe entry).

.EXAMPLE
    pwsh -NoProfile -File .\tools\dev\Start-WinMintSmokeAcceptanceElevated.ps1

.EXAMPLE
    pwsh -NoProfile -File .\tools\dev\Start-WinMintSmokeAcceptanceElevated.ps1 -PushOnly
#>
[CmdletBinding()]
param(
    [string]$ProfilePath = 'tests\profiles\hyper-v-smoke-arm64.json',
    [switch]$PushOnly,
    [switch]$SkipForceBuild,
    [switch]$NoObserve
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot

$startParams = @{
    ProfilePath = $ProfilePath
    Force       = $true
}
if ($PushOnly) { $startParams['PushOnly'] = $true }
if ($NoObserve) { $startParams['NoObserve'] = $true }
if (-not $PushOnly -and -not $SkipForceBuild) {
    $startParams['ForceBuild'] = $true
    $startParams['SmartBuild'] = $false
}

& (Join-Path $repoRoot 'tools\vm\Start-WinMintVmAcceptanceManaged.ps1') @startParams
