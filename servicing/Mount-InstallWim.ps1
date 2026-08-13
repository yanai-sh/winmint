#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
# Mount Source ISO media + install.wim. Params only — no Profile branching.
#
# Root cause (2026-08-02): multi-edition Unmount/Commit stalls; export single-index first.
# Metadata discipline: snapshot/assert Name/Arch/Edition fields; ei.cfg + PID.txt; clear R/O before export.
$sourceIso = $Parameters['sourceIso']
$mountDir = $Parameters['mountDir']
$mediaDir = $Parameters['mediaDir']
$wimIndex = $Parameters['wimIndex']
$workDir = $Parameters['workDirectory']
$sourceIsoSha256 = $Parameters['sourceIsoSha256']
$sourceIsoLength = $Parameters['sourceIsoLength']
$cacheSchema = $Parameters['cacheSchema']
$cacheRoot = $Parameters['cacheRoot']
$imageName = $Parameters['imageName']
$imageArchitecture = $Parameters['architecture']
$imageEdition = $Parameters['imageEdition']
$imageBuild = $Parameters['imageBuild']
if ([string]::IsNullOrWhiteSpace($sourceIso)) { throw 'sourceIso required' }
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }
if ([string]::IsNullOrWhiteSpace($mediaDir)) { throw 'mediaDir required' }
if ([string]::IsNullOrWhiteSpace($wimIndex)) { throw 'wimIndex required' }
if ([string]::IsNullOrWhiteSpace($workDir)) { throw 'workDirectory required' }
if ([string]::IsNullOrWhiteSpace($sourceIsoSha256)) { throw 'sourceIsoSha256 required' }
if ([string]::IsNullOrWhiteSpace($sourceIsoLength)) { throw 'sourceIsoLength required' }
if ([string]::IsNullOrWhiteSpace($cacheSchema)) { throw 'cacheSchema required' }
if ([string]::IsNullOrWhiteSpace($cacheRoot)) { throw 'cacheRoot required' }
if (-not (Test-Path -LiteralPath $sourceIso)) { throw "sourceIso not found: $sourceIso" }

. (Join-Path $PSScriptRoot 'Get-WimMetadata.ps1')
. (Join-Path $PSScriptRoot 'Initialize-SourceMediaCache.ps1')
. (Join-Path $PSScriptRoot 'Resolve-WinMintMount.ps1')

New-Item -ItemType Directory -Force -Path $mountDir | Out-Null

$expectedIdentity = [ordered]@{
    sourceIsoSha256 = $sourceIsoSha256
    wimIndex = [int]$wimIndex
    imageName = $imageName
    architecture = $imageArchitecture
    edition = $imageEdition
    build = $imageBuild
}

Write-Output 'Validating prepared media'
$prepared = Initialize-WinMintPreparedMedia `
    -SourceIso $sourceIso `
    -SourceIsoSha256 $sourceIsoSha256 `
    -SourceIsoLength ([long]$sourceIsoLength) `
    -WimIndex ([int]$wimIndex) `
    -Schema ([int]$cacheSchema) `
    -CacheRoot $cacheRoot `
    -ExpectedIdentity $expectedIdentity

Write-Output 'Copying staged media'
$copied = Copy-WinMintRunMedia `
    -PreparedMedia (Join-Path $prepared.EntryPath 'media') `
    -MediaDir $mediaDir `
    -ExpectedIdentity $expectedIdentity

$wimFile = Join-Path $mediaDir 'sources\install.wim'
Assert-WinMintMountImagePath -ImageFile $wimFile -CacheRoot $cacheRoot

$finalSnapshot = Get-WimMetadataSnapshot -WimFile $wimFile -Index 1
if ([int]$finalSnapshot.IndexCount -ne 1) {
    throw "Staged install.wim has $($finalSnapshot.IndexCount) indexes (need 1)"
}
Assert-WimMetadataPresent -Snapshot $finalSnapshot -Context 'MountInstallWim staged'
if (-not (Test-WinMintSelectedImage -Snapshot $finalSnapshot -ExpectedIdentity $expectedIdentity)) {
    throw 'Staged install.wim does not match the approved selected-image metadata.'
}
Write-WimMetadataEvidence -WorkDirectory $workDir -Document @{
    phase = 'MountInstallWim'; final = $finalSnapshot
}

Write-Output "DISM Mount-Image index=1 → $mountDir"
Write-WinMintMountOwner -Kind install -WorkDirectory $workDir -MountDirectory $mountDir -ImageFile $wimFile -SourceIsoSha256 $sourceIsoSha256 -SourceIndex 1 | Out-Null
$mountClock = [System.Diagnostics.Stopwatch]::StartNew()
& dism.exe /English /Mount-Image /ImageFile:$wimFile /Index:1 /MountDir:$mountDir
$mountClock.Stop()
if ($LASTEXITCODE -ne 0) { throw "DISM Mount-Image failed: $LASTEXITCODE" }

$manifest = Get-Content -LiteralPath (Join-Path $prepared.EntryPath 'manifest.json') -Raw | ConvertFrom-Json
$recoveryAction = [string]$env:WINMINT_RECOVERY_ACTION
if ([string]::IsNullOrWhiteSpace($recoveryAction)) { $recoveryAction = 'none' }
Write-WinMintPreparedMediaResult -Path (Join-Path $workDir 'prepared-media.json') -Document ([ordered]@{
        'source.isoSha256'              = $sourceIsoSha256
        'source.isoLength'              = [long]$sourceIsoLength
        'source.index'                  = [int]$wimIndex
        'mediaCache.schema'             = [int]$cacheSchema
        'mediaCache.key'                = (Join-Path "v$cacheSchema" $sourceIsoSha256 "index-$wimIndex")
        'mediaCache.entryPath'          = $prepared.EntryPath
        'mediaCache.outcome'            = [string]$prepared.Outcome
        'mediaCache.installWimSha256'   = [string]$manifest.installWimSha256
        'mediaCache.bootWimSha256'      = [string]$manifest.bootWimSha256
        'mediaCache.copyMode'           = [string]$copied.CopyMode
        'mediaCache.recoveryAction'     = $recoveryAction
        'mediaCache.previousMedia'      = [string]$copied.PreviousMedia
        'timings.sourceHashMs'          = [int]$prepared.SourceHashMs
        'timings.cacheValidateMs'       = [int]$prepared.CacheValidateMs
        'timings.cachePrepareMs'        = [int]$prepared.CachePrepareMs
        'timings.runMediaCopyMs'        = [int]$copied.CopyMs
        'timings.mountMs'               = [int]$mountClock.ElapsedMilliseconds
    })

Write-Output "MountInstallWim ok"
exit 0
