#Requires -Version 7.6
<#
.SYNOPSIS
  Build clean winmint-v2-seed and future-assets zips into docs/v2/dist (no bin/obj).
#>
[CmdletBinding()]
param(
    [string]$SeedRoot = (Join-Path $PSScriptRoot '..\seed-for-new-repo'),
    [string]$FutureRoot = (Join-Path $PSScriptRoot '..\future-assets'),
    [string]$ZipDir = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'
$SeedRoot = (Resolve-Path -LiteralPath $SeedRoot).Path
$FutureRoot = (Resolve-Path -LiteralPath $FutureRoot).Path
New-Item -ItemType Directory -Force -Path $ZipDir | Out-Null
$ZipDir = (Resolve-Path -LiteralPath $ZipDir).Path
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

$stage = Join-Path $env:TEMP "winmint-v2-pack-$stamp"
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$seedStage = Join-Path $stage 'seed'
New-Item -ItemType Directory -Force -Path $seedStage | Out-Null
# /XD excludes build outputs that would poison Compress-Archive after `just check`
& robocopy $SeedRoot $seedStage /E /NFL /NDL /NJH /NJS /nc /ns /np `
    /XD bin obj .vs /XF *.user | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy seed failed: $LASTEXITCODE" }

$seedZip = Join-Path $ZipDir "winmint-v2-seed-$stamp.zip"
Push-Location $seedStage
try {
    Compress-Archive -Path * -DestinationPath $seedZip -Force
} finally {
    Pop-Location
}

$futureStage = Join-Path $stage 'future-assets'
New-Item -ItemType Directory -Force -Path $futureStage | Out-Null
& robocopy $FutureRoot $futureStage /E /NFL /NDL /NJH /NJS /nc /ns /np /XF winmint_hero_ui.png | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy future failed: $LASTEXITCODE" }

$futureZip = Join-Path $ZipDir "winmint-v2-future-assets-$stamp.zip"
$futureParent = Join-Path $stage 'future-parent'
New-Item -ItemType Directory -Force -Path $futureParent | Out-Null
Move-Item -LiteralPath $futureStage -Destination (Join-Path $futureParent 'future-assets')
Compress-Archive -Path (Join-Path $futureParent 'future-assets') -DestinationPath $futureZip -Force

Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Wrote:`n  $seedZip`n  $futureZip"
& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Verify-StarterPackage.ps1') -ZipDir $ZipDir
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
exit 0
