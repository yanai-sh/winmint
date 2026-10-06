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
. (Join-Path $PSScriptRoot '..\tools\host\Write-WinMintHostProgress.ps1')

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

function Get-WinMintHeartbeatSha256 {
    param([Parameter(Mandatory)] [string] $Path)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $buffer = New-Object byte[] (8MB)
        $total = $stream.Length
        if ($total -le 0) { throw "quality hash empty: $Path" }
        $done = [int64]0
        $mark = [int64]256MB
        Write-Output ("quality hash 0% 0/{0:n0} MB" -f ($total / 1MB))
        Write-WinMintHostProgress -Activity 'quality hash' -Status ("0/{0:n0} MB" -f ($total / 1MB)) -PercentComplete 0
        while (($n = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $null = $sha256.TransformBlock($buffer, 0, $n, $null, 0)
            $done += $n
            if ($done -ge $mark -or $done -eq $total) {
                $pct = [math]::Floor(100.0 * $done / $total)
                Write-Output ("quality hash {0}% {1:n0}/{2:n0} MB" -f $pct, ($done / 1MB), ($total / 1MB))
                Write-WinMintHostProgress -Activity 'quality hash' -Status ("{0:n0}/{1:n0} MB" -f ($done / 1MB), ($total / 1MB)) -PercentComplete ([int]$pct)
                while ($mark -le $done) { $mark += 256MB }
            }
        }
        $empty = New-Object byte[] 0
        $null = $sha256.TransformFinalBlock($empty, 0, 0)
        Write-WinMintHostProgress -Activity 'quality hash' -Completed
        return ([BitConverter]::ToString($sha256.Hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $stream.Dispose()
        $sha256.Dispose()
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
Write-Output "quality package-set start Version=$($snap.Version) UBR=$imageUbr"

$set = Get-WinMintQualityPackageSet `
    -Version ([string]$snap.Version) `
    -Architecture ([string]$snap.Architecture) `
    -ImageUbr $imageUbr

$skipped = [pscustomobject]@{
    Skipped   = $true
    Kb        = $set.Kb
    UbrBefore = [string]$imageUbr
    UbrAfter  = [string]$imageUbr
    Sha256    = ''
}

if ($set.Skipped) {
    Write-WinMintQualityPackageLeaf -PackageDir $QualityPackageDir -Kind boot -Leaf @()
    Write-WinMintQualityPackageLeaf -PackageDir $QualityPackageDir -Kind winre -Leaf @()
    Write-QualityEvidence -State $skipped
    Write-Output "AddQualityUpdates skipped (image UBR $imageUbr >= Catalog $($set.Kb) $($set.PackageUbr))"
    exit 0
}

$staging = Join-Path $WorkDirectory 'quality-staging'
New-Item -ItemType Directory -Force -Path $staging | Out-Null
try {
    Write-Output "Catalog BITS start $($set.Kb)"
    $lcuPath = Get-WinMintCatalogPayload -UpdateId $set.UpdateId -CacheRoot $QualityCacheRoot `
        -Kb $set.Kb -Architecture $set.Architecture -StagingDir $staging
    if (-not (Test-WinMintQualityKbLeaf -Name (Split-Path -Leaf $lcuPath) -Kb $set.Kb)) {
        throw "Combined LCU payload leaf is not $($set.Kb): $lcuPath"
    }
    $lcuLeaf = Split-Path -Leaf $lcuPath
    $lcuMb = [math]::Round((Get-Item -LiteralPath $lcuPath).Length / 1MB)
    Write-Output "quality hash start $lcuLeaf ${lcuMb}MB"
    $sha = @(Get-WinMintHeartbeatSha256 -Path $lcuPath) | Select-Object -Last 1
    Write-Output "quality hash ok $lcuLeaf"
    Copy-Item -LiteralPath $lcuPath -Destination (Join-Path $QualityPackageDir $lcuLeaf) -Force

    $extract = Join-Path $staging 'expand'
    Write-Output "quality expand start $lcuLeaf"
    $ssuPath = Expand-WinMintQualitySsu -MsuPath $lcuPath -Destination $extract
    $ssuLeaf = Split-Path -Leaf $ssuPath
    Write-Output "quality expand ok $ssuLeaf"
    Copy-Item -LiteralPath $ssuPath -Destination (Join-Path $QualityPackageDir $ssuLeaf) -Force

    $bootStlSrc = Find-WinMintQualityBootStl -ExtractDir $extract
    if ($bootStlSrc) {
        Copy-Item -LiteralPath $bootStlSrc -Destination (Join-Path $QualityPackageDir 'boot.stl') -Force
    }

    $checkpointLeaves = [System.Collections.Generic.List[string]]::new()
    foreach ($ck in @($set.Checkpoints)) {
        Write-Output "quality checkpoint $($ck.Kb)"
        $ckPath = Get-WinMintCatalogPayload -UpdateId $ck.UpdateId -CacheRoot $QualityCacheRoot `
            -Kb $ck.Kb -Architecture $set.Architecture -StagingDir $staging
        $ckLeaf = Split-Path -Leaf $ckPath
        Copy-Item -LiteralPath $ckPath -Destination (Join-Path $QualityPackageDir $ckLeaf) -Force
        $checkpointLeaves.Add($ckLeaf)
    }

    $setupLeaf = ''
    $safeLeaf = ''
    if ($set.Setup) {
        $setupPath = Get-WinMintCatalogPayload -UpdateId $set.Setup.UpdateId -CacheRoot $QualityCacheRoot `
            -Kb $set.Setup.Kb -Architecture $set.Architecture -StagingDir $staging
        $setupLeaf = Split-Path -Leaf $setupPath
        Copy-Item -LiteralPath $setupPath -Destination (Join-Path $QualityPackageDir $setupLeaf) -Force
    }
    if ($set.SafeOs) {
        $safePath = Get-WinMintCatalogPayload -UpdateId $set.SafeOs.UpdateId -CacheRoot $QualityCacheRoot `
            -Kb $set.SafeOs.Kb -Architecture $set.Architecture -StagingDir $staging
        $safeLeaf = Split-Path -Leaf $safePath
        Copy-Item -LiteralPath $safePath -Destination (Join-Path $QualityPackageDir $safeLeaf) -Force
    }

    Write-Output "quality packages apply"
    $null = Invoke-WinMintQualityPackagesApply `
        -MountDir $MountDir `
        -PackageDir $QualityPackageDir `
        -SsuLeaf $ssuLeaf `
        -CheckpointLeaves @($checkpointLeaves) `
        -LcuLeaf $lcuLeaf `
        -SetupLeaf $setupLeaf `
        -SafeOsLeaf $safeLeaf `
        -Family $set.Family `
        -PackageUbr $set.PackageUbr `
        -Architecture $set.Architecture

    Write-QualityEvidence -State ([pscustomobject]@{
            Skipped   = $false
            Kb        = $set.Kb
            UbrBefore = [string]$imageUbr
            UbrAfter  = [string]$set.PackageUbr
            Sha256    = $sha
        })
    Write-Output "AddQualityUpdates ok $($set.Kb) $imageUbr -> $($set.PackageUbr)"
}
finally {
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit 0
