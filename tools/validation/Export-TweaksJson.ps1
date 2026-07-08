#Requires -Version 7.6
<#
.SYNOPSIS
  Regenerates config/tweaks.json public metadata from tweak modules (parity helper).
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

$ErrorActionPreference = 'Stop'
$tweakRegistry = Join-Path $RepositoryRoot 'src\runtime\image\Private\Image\Tweaks\TweakRegistry.ps1'
$tweaksJson = Join-Path $RepositoryRoot 'config\tweaks.json'
. $tweakRegistry

$entries = @(Get-WinMintSelectedRegistryTweaks -BuildConfig @{ RegistryTweaks = @($script:RegistryTweaks | ForEach-Object { $_.id }) })
$public = @($script:RegistryTweaks | ForEach-Object {
        [ordered]@{
            id = $_.id
            description = $_.description
            phase = $_.phase
            risk = $_.risk
            reversible = $_.reversible
        }
    })
$public | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tweaksJson -Encoding UTF8
Write-Host "Wrote $($public.Count) tweak metadata entries to $tweaksJson"
