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
$imageName = $Parameters['imageName']
$imageArchitecture = $Parameters['architecture']
$imageEdition = $Parameters['imageEdition']
$imageBuild = $Parameters['imageBuild']
if ([string]::IsNullOrWhiteSpace($sourceIso)) { throw 'sourceIso required' }
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }
if ([string]::IsNullOrWhiteSpace($mediaDir)) { throw 'mediaDir required' }
if ([string]::IsNullOrWhiteSpace($wimIndex)) { throw 'wimIndex required' }
if ([string]::IsNullOrWhiteSpace($workDir)) { throw 'workDirectory required' }
if (-not (Test-Path -LiteralPath $sourceIso)) { throw "sourceIso not found: $sourceIso" }

. (Join-Path $PSScriptRoot 'Get-WimMetadata.ps1')
. (Join-Path $PSScriptRoot 'Test-MediaIdentity.ps1')

New-Item -ItemType Directory -Force -Path $mountDir | Out-Null

$wimFile = Join-Path $mediaDir 'sources\install.wim'
$marker = Join-Path $mediaDir '.winmint-media-identity.json'
$expectedIdentity = [ordered]@{
    sourceIsoSha256 = $sourceIsoSha256
    wimIndex = [int]$wimIndex
    imageName = $imageName
    architecture = $imageArchitecture
    edition = $imageEdition
    build = $imageBuild
}

if (Test-Path -LiteralPath $mediaDir) {
    Remove-Item -LiteralPath $mediaDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $mediaDir | Out-Null
Write-Output "Mounting ISO $sourceIso"
$disk = Mount-DiskImage -ImagePath $sourceIso -PassThru
try {
    Start-Sleep -Seconds 2
    $letter = ($disk | Get-Volume | Select-Object -First 1).DriveLetter
    if ([string]::IsNullOrWhiteSpace($letter)) { throw 'ISO mounted but no drive letter' }
    $isoRoot = "${letter}:"
    Write-Output "ISO at $isoRoot — copying media to $mediaDir"
    & robocopy.exe $isoRoot $mediaDir /E /COPY:DAT /R:2 /W:2 /NFL /NDL /NJH /NJS /NP | Out-Host
    $rc = $LASTEXITCODE
    if ($rc -ge 8) { throw "robocopy failed with exit $rc" }
}
finally {
    Dismount-DiskImage -ImagePath $sourceIso | Out-Null
}

Get-ChildItem -LiteralPath $mediaDir -Recurse -Force -File | ForEach-Object {
    if ($_.IsReadOnly) { $_.IsReadOnly = $false }
}

if (-not (Test-Path -LiteralPath $wimFile)) {
    $esd = Join-Path $mediaDir 'sources\install.esd'
    if (Test-Path -LiteralPath $esd) { throw 'install.esd present; convert to WIM before Apply (not implemented)' }
    throw "install.wim missing under $mediaDir\sources"
}

$mountIndex = [int]$wimIndex
$probe = Get-WimMetadataSnapshot -WimFile $wimFile -Index 1
$indexCount = [int]$probe.IndexCount
if ($indexCount -eq 1) {
    $mountIndex = 1
    $beforeExport = $probe
}
else {
    $beforeExport = Get-WimMetadataSnapshot -WimFile $wimFile -Index $mountIndex
}

if ($indexCount -gt 1) {
    Write-Output "Multi-index WIM ($indexCount indexes) — exporting index $wimIndex ($($beforeExport.Name))"
    Clear-WimReadOnly -WimFile $wimFile
    $tmp = Join-Path $mediaDir 'sources\install.single.wim'
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    & dism.exe /English /Export-Image /SourceImageFile:$wimFile /SourceIndex:$wimIndex /DestinationImageFile:$tmp /Compress:fast
    if ($LASTEXITCODE -ne 0) { throw "Export-Image (single-index) failed: $LASTEXITCODE" }
    Remove-Item -LiteralPath $wimFile -Force
    Move-Item -LiteralPath $tmp -Destination $wimFile -Force
    Clear-WimReadOnly -WimFile $wimFile
    $mountIndex = 1
    $afterExport = Get-WimMetadataSnapshot -WimFile $wimFile -Index 1
    if ([int]$afterExport.IndexCount -ne 1) {
        throw "After single-index export, install.wim has $($afterExport.IndexCount) indexes (need 1)"
    }
    Assert-WimMetadataStable -Before $beforeExport -After $afterExport -Context 'MountInstallWim single-index export'
    Write-WinMintEditionConfig -MediaDir $mediaDir -Snapshot $afterExport
    Write-WimMetadataEvidence -WorkDirectory $workDir -Document @{
        phase = 'MountInstallWim.export'; before = $beforeExport; after = $afterExport; final = $afterExport
    }
    Write-Output "Single-image WIM ready (mount index 1); size=$((Get-Item -LiteralPath $wimFile).Length)"
}
else {
    if ($indexCount -ne 1) {
        throw "Expected single-image WIM or multi-index export; indexCount=$indexCount"
    }
    Clear-WimReadOnly -WimFile $wimFile
    Assert-WimMetadataPresent -Snapshot $beforeExport -Context 'MountInstallWim single'
    Write-WinMintEditionConfig -MediaDir $mediaDir -Snapshot $beforeExport
    Write-WimMetadataEvidence -WorkDirectory $workDir -Document @{ phase = 'MountInstallWim.single'; final = $beforeExport }
    Write-Output "WIM already single-image; mount index $mountIndex ($($beforeExport.Name))"
}

$finalSnapshot = Get-WimMetadataSnapshot -WimFile $wimFile -Index 1
if (-not (Test-WinMintSelectedImage -Snapshot $finalSnapshot -ExpectedIdentity $expectedIdentity)) {
    throw 'Staged install.wim does not match the approved selected-image metadata.'
}
Write-WinMintMediaIdentity -MarkerPath $marker -ExpectedIdentity $expectedIdentity

Write-Output "DISM Mount-Image index=$mountIndex → $mountDir"
& dism.exe /English /Mount-Image /ImageFile:$wimFile /Index:$mountIndex /MountDir:$mountDir
if ($LASTEXITCODE -ne 0) { throw "DISM Mount-Image failed: $LASTEXITCODE" }

Write-Output "MountInstallWim ok"
exit 0
