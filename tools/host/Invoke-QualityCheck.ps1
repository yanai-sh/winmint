#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Maintainer-only live Catalog reconcile. Not in `just check`.

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'servicing\Resolve-WinMintQualityUpdate.ps1')

# WinMint supports 25H2+ only; do not probe older trains.
foreach ($pair in @(
        @{ Label = '25H2'; Version = '10.0.26200.1' }
    )) {
    $resolved = Invoke-WinMintQualityCatalogResolve -Version $pair.Version -Architecture 'ARM64' -ImageUbr 0
    Write-Output "$($pair.Label) ARM64 B-release $($resolved.Kb) UBR $($resolved.PackageUbr)"
    Write-Output $resolved.Title
}

Write-Output 'quality-check ok'
exit 0
