#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
# Commit + unmount. Params from BuildPlan only — no Profile branching.
$mountDir = $Parameters['mountDir']
$wimOut = $Parameters['wimOut']
$mediaDir = $Parameters['mediaDir']
$lane = $Parameters['lane']
$compression = $Parameters['compression']
$cleanup = $Parameters['cleanup']
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }
if ([string]::IsNullOrWhiteSpace($wimOut)) { throw 'wimOut required' }
if ([string]::IsNullOrWhiteSpace($mediaDir)) { throw 'mediaDir required' }
if ([string]::IsNullOrWhiteSpace($compression)) { throw 'compression required' }
if ([string]::IsNullOrWhiteSpace($cleanup)) { throw 'cleanup required' }

$wimFile = Join-Path $mediaDir 'sources\install.wim'
if (-not (Test-Path -LiteralPath $wimFile)) { throw "install.wim missing: $wimFile" }

if ($cleanup -eq 'full') {
    Write-Host "DISM Cleanup-Image /StartComponentCleanup /ResetBase ($mountDir)"
    & dism.exe /English /Image:$mountDir /Cleanup-Image /StartComponentCleanup /ResetBase
    if ($LASTEXITCODE -ne 0) { throw "DISM Cleanup-Image failed: $LASTEXITCODE" }
}
elseif ($cleanup -ne 'skip') {
    throw "unsupported cleanup='$cleanup' (expected skip|full)"
}

Write-Host "DISM Unmount-Image /Commit ($mountDir) lane=$lane compression=$compression cleanup=$cleanup"
& dism.exe /English /Unmount-Image /MountDir:$mountDir /Commit
if ($LASTEXITCODE -ne 0) { throw "DISM Unmount-Image failed: $LASTEXITCODE" }

if ($compression -eq 'max') {
    $exportTmp = Join-Path $mediaDir 'sources\install.export.wim'
    if (Test-Path -LiteralPath $exportTmp) { Remove-Item -LiteralPath $exportTmp -Force }
    Write-Host "DISM Export-Image /Compress:max → $exportTmp"
    & dism.exe /English /Export-Image /SourceImageFile:$wimFile /SourceIndex:1 /DestinationImageFile:$exportTmp /Compress:max
    if ($LASTEXITCODE -ne 0) { throw "DISM Export-Image failed: $LASTEXITCODE" }
    Remove-Item -LiteralPath $wimFile -Force
    Move-Item -LiteralPath $exportTmp -Destination $wimFile -Force
}
elseif ($compression -ne 'fast') {
    throw "unsupported compression='$compression' (expected fast|max)"
}

if (Test-Path -LiteralPath $wimOut) { Remove-Item -LiteralPath $wimOut -Force }
New-Item -ItemType HardLink -Path $wimOut -Target $wimFile -ErrorAction SilentlyContinue | Out-Null
if (-not (Test-Path -LiteralPath $wimOut)) {
    # Hardlink may fail across volumes — copy is fine for Smoke.
    Copy-Item -LiteralPath $wimFile -Destination $wimOut -Force
}

Write-Host "ExportWim ok lane=$lane compression=$compression cleanup=$cleanup wimOut=$wimOut"
exit 0
