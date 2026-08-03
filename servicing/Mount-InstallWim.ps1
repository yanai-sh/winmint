#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
# Mount Source ISO media + install.wim. Params only — no Profile branching.
#
# Root cause (2026-08-02): mounting index N of a multi-edition consumer WIM (~7GB,
# Home+HomeSL+Pro) then Unmount/Commit rewrites the whole multi-image file.
# DISM "Saving image" crawled to ~4% over hours then wimserv CPU flatlined.
# Fix: export the requested index to a single-image WIM before mount; commit stays O(delta).
$sourceIso = $Parameters['sourceIso']
$mountDir = $Parameters['mountDir']
$mediaDir = $Parameters['mediaDir']
$wimIndex = $Parameters['wimIndex']
$reuseMedia = ($Parameters['reuseMedia'] -eq 'true')
if ([string]::IsNullOrWhiteSpace($sourceIso)) { throw 'sourceIso required' }
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }
if ([string]::IsNullOrWhiteSpace($mediaDir)) { throw 'mediaDir required' }
if ([string]::IsNullOrWhiteSpace($wimIndex)) { throw 'wimIndex required' }
if (-not $reuseMedia -and -not (Test-Path -LiteralPath $sourceIso)) { throw "sourceIso not found: $sourceIso" }

New-Item -ItemType Directory -Force -Path $mountDir, $mediaDir | Out-Null

$wimFile = Join-Path $mediaDir 'sources\install.wim'
$marker = Join-Path $mediaDir 'sources\.winmint-single-index'

function Get-WimIndexCount {
    param([string] $Path)
    $text = & dism.exe /English /Get-WimInfo /WimFile:$Path 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Get-WimInfo failed: $LASTEXITCODE" }
    return ([regex]::Matches($text, '(?m)^Index : \d+\s*$')).Count
}

if ($reuseMedia) {
    if (-not (Test-Path -LiteralPath $wimFile)) {
        throw "reuse-media: install.wim missing at $wimFile — re-run without --reuse-media"
    }
    if (-not (Test-Path -LiteralPath $marker)) {
        throw "reuse-media: marker missing at $marker — re-run without --reuse-media"
    }
    $indexCount = Get-WimIndexCount -Path $wimFile
    if ($indexCount -ne 1) {
        throw "reuse-media: install.wim has $indexCount indexes (need 1) — re-run without --reuse-media"
    }
    $existing = Get-Item -LiteralPath $wimFile
    if ($existing.IsReadOnly) { $existing.IsReadOnly = $false }
    Write-Output "reuse-media: skipping ISO copy/export; mounting single-image WIM index 1"
    Write-Output "DISM Mount-Image index=1 → $mountDir"
    & dism.exe /English /Mount-Image /ImageFile:$wimFile /Index:1 /MountDir:$mountDir
    if ($LASTEXITCODE -ne 0) { throw "DISM Mount-Image failed: $LASTEXITCODE" }
    Write-Output "MountInstallWim ok"
    exit 0
}

$needCopy = -not (Test-Path -LiteralPath $wimFile)
if (-not $needCopy) {
    $existing = Get-Item -LiteralPath $wimFile
    if ($existing.IsReadOnly) { $existing.IsReadOnly = $false }
    Write-Output "Reusing media WIM at $wimFile"
}
else {
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

    # ISO media is read-only; DISM needs a writable WIM to mount/commit.
    Get-ChildItem -LiteralPath $mediaDir -Recurse -Force -File | ForEach-Object {
        if ($_.IsReadOnly) { $_.IsReadOnly = $false }
    }
}

if (-not (Test-Path -LiteralPath $wimFile)) {
    $esd = Join-Path $mediaDir 'sources\install.esd'
    if (Test-Path -LiteralPath $esd) { throw 'install.esd present; convert to WIM before Apply (not implemented)' }
    throw "install.wim missing under $mediaDir\sources"
}

$mountIndex = [int]$wimIndex
$indexCount = Get-WimIndexCount -Path $wimFile

if ($indexCount -gt 1) {
    Write-Output "Multi-index WIM ($indexCount indexes) — exporting index $wimIndex to single-image WIM before mount"
    $tmp = Join-Path $mediaDir 'sources\install.single.wim'
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    # Compress:fast keeps Smoke Test lane cheap; Release recompress is ExportWim ticket 09.
    & dism.exe /English /Export-Image /SourceImageFile:$wimFile /SourceIndex:$wimIndex /DestinationImageFile:$tmp /Compress:fast
    if ($LASTEXITCODE -ne 0) { throw "Export-Image (single-index) failed: $LASTEXITCODE" }
    Remove-Item -LiteralPath $wimFile -Force
    Move-Item -LiteralPath $tmp -Destination $wimFile -Force
    Set-Content -LiteralPath $marker -Value "sourceIndex=$wimIndex" -Encoding utf8
    $mountIndex = 1
    Write-Output "Single-image WIM ready (mount index 1); size=$((Get-Item -LiteralPath $wimFile).Length)"
}
elseif (Test-Path -LiteralPath $marker) {
    $mountIndex = 1
    Write-Output "Reusing single-image WIM (marker present); mount index 1"
}
else {
    Write-Output "WIM already single-image; mount index $mountIndex"
}

Write-Output "DISM Mount-Image index=$mountIndex → $mountDir"
& dism.exe /English /Mount-Image /ImageFile:$wimFile /Index:$mountIndex /MountDir:$mountDir
if ($LASTEXITCODE -ne 0) { throw "DISM Mount-Image failed: $LASTEXITCODE" }

Write-Output "MountInstallWim ok"
exit 0
