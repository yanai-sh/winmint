#requires -Version 7.6
Set-StrictMode -Version Latest
# Shared live Catalog B-release reconcile (ADR-013). Dot-source from host scripts.

function Get-WinMintQualityTrainPairs {
    # WinMint supports 25H2+ only; do not probe older trains.
    return , @(
        [pscustomobject]@{ Label = '25H2'; Version = '10.0.26200.1' }
    )
}

function Invoke-WinMintQualityReconcile {
    param(
        [scriptblock] $CatalogResolver = {
            param([string] $Version, [string] $Architecture, [int] $ImageUbr)
            Invoke-WinMintQualityCatalogResolve -Version $Version -Architecture $Architecture -ImageUbr $ImageUbr
        }
    )

    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($pair in Get-WinMintQualityTrainPairs) {
        $resolved = & $CatalogResolver $pair.Version 'ARM64' 0
        $out.Add([pscustomobject]@{
                Label      = $pair.Label
                Version    = $pair.Version
                Kb         = $resolved.Kb
                Title      = $resolved.Title
                PackageUbr = [int]$resolved.PackageUbr
            })
    }
    return , $out
}

function Write-WinMintQualityReconcileLines {
    param([Parameter(Mandatory)] $Rows)
    foreach ($r in $Rows) {
        Write-Output "$($r.Label) ARM64 B-release $($r.Kb) UBR $($r.PackageUbr)"
        Write-Output $r.Title
    }
}
