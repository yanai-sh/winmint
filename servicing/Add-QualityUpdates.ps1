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
    $lcuPath = Get-WinMintCatalogPayload -UpdateId $resolved.UpdateId -CacheRoot $QualityCacheRoot `
        -Kb $resolved.Kb -Architecture 'ARM64' -StagingDir $staging
    $sha = (Get-FileHash -LiteralPath $lcuPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $lcuLeaf = Split-Path -Leaf $lcuPath
    Copy-Item -LiteralPath $lcuPath -Destination (Join-Path $QualityPackageDir $lcuLeaf) -Force

    $extract = Join-Path $staging 'expand'
    $ssuPath = Expand-WinMintQualitySsu -MsuPath $lcuPath -Destination $extract
    $ssuLeaf = Split-Path -Leaf $ssuPath
    Copy-Item -LiteralPath $ssuPath -Destination (Join-Path $QualityPackageDir $ssuLeaf) -Force

    $bootStlSrc = Find-WinMintQualityBootStl -ExtractDir $extract
    if ($bootStlSrc) {
        Copy-Item -LiteralPath $bootStlSrc -Destination (Join-Path $QualityPackageDir 'boot.stl') -Force
    }

    $checkpointLeaves = [System.Collections.Generic.List[string]]::new()
    foreach ($ckb in @(ConvertFrom-WinMintCatalogCheckpointKb -Text $resolved.DetailsHtml -TargetKb $resolved.Kb)) {
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

    $install = [System.Collections.Generic.List[string]]::new()
    $install.Add($ssuLeaf)
    foreach ($c in $checkpointLeaves) { $install.Add($c) }
    $install.Add($lcuLeaf)

    $boot = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $install) { $boot.Add($p) }
    if ($setupLeaf) { $boot.Add($setupLeaf) }

    $winre = [System.Collections.Generic.List[string]]::new()
    $winre.Add($ssuLeaf)
    if ($safeLeaf) { $winre.Add($safeLeaf) }

    foreach ($leaf in $install) {
        Invoke-WinMintDismAddPackage -MountDir $MountDir -PackagePath (Join-Path $QualityPackageDir $leaf)
    }

    $packages = & dism.exe /English /Image:$MountDir /Get-Packages 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "DISM /Get-Packages failed: $LASTEXITCODE" }
    Test-WinMintRollupFixPresent -GetPackagesText $packages -Family $resolved.Family -Ubr $resolved.PackageUbr -Architecture 'ARM64'

    Write-WinMintQualityPackageLeaf -PackageDir $QualityPackageDir -Kind boot -Leaf @($boot)
    Write-WinMintQualityPackageLeaf -PackageDir $QualityPackageDir -Kind winre -Leaf @($winre)
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
