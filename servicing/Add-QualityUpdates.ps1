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
        Write-Host ("quality hash 0% 0/{0:n0} MB" -f ($total / 1MB))
        while (($n = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $null = $sha256.TransformBlock($buffer, 0, $n, $null, 0)
            $done += $n
            if ($done -ge $mark -or $done -eq $total) {
                $pct = [math]::Floor(100.0 * $done / $total)
                Write-Host ("quality hash {0}% {1:n0}/{2:n0} MB" -f $pct, ($done / 1MB), ($total / 1MB))
                while ($mark -le $done) { $mark += 256MB }
            }
        }
        $empty = New-Object byte[] 0
        $null = $sha256.TransformFinalBlock($empty, 0, 0)
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
    Write-Output "Catalog BITS start $($resolved.Kb)"
    $lcuPath = Get-WinMintCatalogPayload -UpdateId $resolved.UpdateId -CacheRoot $QualityCacheRoot `
        -Kb $resolved.Kb -Architecture 'ARM64' -StagingDir $staging
    if (-not (Test-WinMintQualityKbLeaf -Name (Split-Path -Leaf $lcuPath) -Kb $resolved.Kb)) {
        throw "Combined LCU payload leaf is not $($resolved.Kb): $lcuPath"
    }
    $lcuLeaf = Split-Path -Leaf $lcuPath
    $lcuMb = [math]::Round((Get-Item -LiteralPath $lcuPath).Length / 1MB)
    Write-Output "quality hash start $lcuLeaf ${lcuMb}MB"
    $sha = Get-WinMintHeartbeatSha256 -Path $lcuPath
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
    foreach ($ckb in @(ConvertFrom-WinMintCatalogCheckpointKb -Text $resolved.DetailsHtml -TargetKb $resolved.Kb)) {
        Write-Output "quality checkpoint $ckb"
        $ckHtml = Invoke-WinMintCatalogSearchHtml -Query "$ckb ARM64-based Systems"
        $ckRows = ConvertFrom-WinMintCatalogSearchHtml -Html $ckHtml
        $ckHit = @($ckRows | Where-Object { $_.Kb -eq $ckb -and $_.Title -match 'ARM64-based Systems' } | Select-Object -First 1)
        if ($ckHit.Count -lt 1) {
            throw "Catalog checkpoint $ckb has no ARM64 payload"
        }
        $ckPath = Get-WinMintCatalogPayload -UpdateId $ckHit[0].UpdateId -CacheRoot $QualityCacheRoot `
            -Kb $ckb -Architecture 'ARM64' -StagingDir $staging
        $ckLeaf = Split-Path -Leaf $ckPath
        Copy-Item -LiteralPath $ckPath -Destination (Join-Path $QualityPackageDir $ckLeaf) -Force
        $checkpointLeaves.Add($ckLeaf)
    }

    $month = ''
    if ($resolved.Title -match '^(\d{4}-\d{2})') { $month = $Matches[1] }
    $setupLeaf = ''
    $safeLeaf = ''
    $duHtml = Invoke-WinMintCatalogSearchHtml -Query "Dynamic Update for Windows 11 Version $($resolved.Label) ARM64-based Systems"
    $duRows = ConvertFrom-WinMintCatalogSearchHtml -Html $duHtml
    $setup = Select-WinMintDynamicUpdate -Rows $duRows -FamilyLabel $resolved.Label -Architecture 'ARM64' -Kind Setup -MonthPrefix $month
    if ($setup -and $setup.Kb) {
        $setupPath = Get-WinMintCatalogPayload -UpdateId $setup.UpdateId -CacheRoot $QualityCacheRoot `
            -Kb $setup.Kb -Architecture 'ARM64' -StagingDir $staging
        $setupLeaf = Split-Path -Leaf $setupPath
        Copy-Item -LiteralPath $setupPath -Destination (Join-Path $QualityPackageDir $setupLeaf) -Force
    }
    $safe = Select-WinMintDynamicUpdate -Rows $duRows -FamilyLabel $resolved.Label -Architecture 'ARM64' -Kind SafeOS -MonthPrefix $month
    if ($safe -and $safe.Kb) {
        $safePath = Get-WinMintCatalogPayload -UpdateId $safe.UpdateId -CacheRoot $QualityCacheRoot `
            -Kb $safe.Kb -Architecture 'ARM64' -StagingDir $staging
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
        -Family $resolved.Family `
        -PackageUbr $resolved.PackageUbr `
        -Architecture 'ARM64'

    Write-QualityEvidence -State ([pscustomobject]@{
            Skipped   = $false
            Kb        = $resolved.Kb
            UbrBefore = [string]$imageUbr
            UbrAfter  = [string]$resolved.PackageUbr
            Sha256    = $sha
        })
    Write-Output "AddQualityUpdates ok $($resolved.Kb) $imageUbr -> $($resolved.PackageUbr)"
}
finally {
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit 0
