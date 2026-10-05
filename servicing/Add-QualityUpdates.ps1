#requires -Version 7.6
param(
    [Parameter(Mandatory)] [string] $MountDir,
    [Parameter(Mandatory)] [string] $MediaDir,
    [Parameter(Mandatory)] [string] $WorkDirectory,
    [Parameter(Mandatory)] [string] $QualityCacheRoot,
    [Parameter(Mandatory)] [string] $QualityPackageDir
)
# Same-train Catalog LCU on the staged install.wim mount (ADR-013). Splat-only.

. (Join-Path $PSScriptRoot 'Get-WimMetadata.ps1')
. (Join-Path $PSScriptRoot 'Resolve-WinMintQualityUpdate.ps1')
. (Join-Path $PSScriptRoot 'Save-WinMintDigestMap.ps1')

function Write-QualityEvidence {
    param($State)
    Save-WinMintDigestMap -WorkDirectory $WorkDirectory -Digests @{
        'lcu.kb'        = [string]$State.Kb
        'lcu.ubrBefore' = [string]$State.UbrBefore
        'lcu.ubrAfter'  = [string]$State.UbrAfter
        'lcu.sha256'    = [string]$State.Sha256
        'lcu.skipped'   = $(if ($State.Skipped) { 'true' } else { 'false' })
    }
}

$wimFile = Join-Path $MediaDir 'sources\install.wim'
if (-not (Test-Path -LiteralPath $wimFile)) { throw "install.wim missing: $wimFile" }
if (-not (Test-Path -LiteralPath $MountDir)) { throw "install mount missing: $MountDir" }

New-Item -ItemType Directory -Force -Path $QualityCacheRoot | Out-Null
if (Test-Path -LiteralPath $QualityPackageDir) {
    Remove-Item -LiteralPath $QualityPackageDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $QualityPackageDir | Out-Null

$snap = Get-WimMetadataSnapshot -WimFile $wimFile -Index 1
$imageUbr = 0
if (-not [int]::TryParse([string]$snap.Build, [ref]$imageUbr)) {
    throw "WIM ServicePack Build is not an integer UBR: $($snap.Build)"
}
Write-Output "AddQualityUpdates start Version=$($snap.Version) UBR=$imageUbr"
Write-Output "Catalog search start Version=$($snap.Version) UBR=$imageUbr"

$resolved = Invoke-WinMintQualityCatalogResolve `
    -Version ([string]$snap.Version) `
    -Architecture ([string]$snap.Architecture) `
    -ImageUbr $imageUbr

$skipped = [pscustomobject]@{
    Skipped   = $true
    Kb        = $resolved.Kb
    UbrBefore = [string]$imageUbr
    UbrAfter  = [string]$imageUbr
    Sha256    = ''
}

if ($resolved.Skipped) {
    Write-WinMintQualityPackageLeaf -PackageDir $QualityPackageDir -Kind boot -Leaf @()
    Write-WinMintQualityPackageLeaf -PackageDir $QualityPackageDir -Kind winre -Leaf @()
    Write-QualityEvidence -State $skipped
    Write-Output "AddQualityUpdates skipped (image UBR $imageUbr >= Catalog $($resolved.Kb) $($resolved.PackageUbr))"
    exit 0
}

$staging = Join-Path $WorkDirectory 'quality-staging'
New-Item -ItemType Directory -Force -Path $staging | Out-Null
try {
    $staged = Invoke-WinMintQualityPackageStage `
        -Resolved $resolved `
        -PackageDir $QualityPackageDir `
        -CacheRoot $QualityCacheRoot `
        -StagingDir $staging

    Write-Output "quality packages apply"
    $null = Invoke-WinMintQualityPackagesApply `
        -MountDir $MountDir `
        -PackageDir $QualityPackageDir `
        -SsuLeaf $staged.SsuLeaf `
        -CheckpointLeaves @($staged.CheckpointLeaves) `
        -LcuLeaf $staged.LcuLeaf `
        -SetupLeaf $staged.SetupLeaf `
        -SafeOsLeaf $staged.SafeOsLeaf `
        -Family $resolved.Family `
        -PackageUbr $resolved.PackageUbr `
        -Architecture 'ARM64'

    Write-QualityEvidence -State ([pscustomobject]@{
            Skipped   = $false
            Kb        = $resolved.Kb
            UbrBefore = [string]$imageUbr
            UbrAfter  = [string]$resolved.PackageUbr
            Sha256    = $staged.Sha256
        })
    Write-Output "AddQualityUpdates ok $($resolved.Kb) $imageUbr -> $($resolved.PackageUbr)"
}
finally {
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit 0
