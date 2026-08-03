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

# Fail closed: never Unmount/Commit a multi-edition WIM (hours-long stall / wimserv flatline).
$wimInfo = & dism.exe /English /Get-WimInfo /WimFile:$wimFile 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Get-WimInfo failed before commit: $LASTEXITCODE" }
$indexCount = ([regex]::Matches($wimInfo, '(?m)^Index : \d+\s*$')).Count
if ($indexCount -ne 1) {
    throw "Refusing Unmount/Commit: install.wim has $indexCount indexes (need 1). Mount-InstallWim must export a single-image WIM first."
}

if ($cleanup -eq 'full') {
    Write-Host "DISM Cleanup-Image /StartComponentCleanup /ResetBase ($mountDir)"
    & dism.exe /English /Image:$mountDir /Cleanup-Image /StartComponentCleanup /ResetBase
    if ($LASTEXITCODE -ne 0) { throw "DISM Cleanup-Image failed: $LASTEXITCODE" }
}
elseif ($cleanup -ne 'skip') {
    throw "unsupported cleanup='$cleanup' (expected skip|full)"
}

Write-Host "DISM Unmount-Image /Commit ($mountDir) lane=$lane compression=$compression cleanup=$cleanup"
# Requires single-image WIM (Mount-InstallWim exports Pro-only). Committing a multi-edition
# consumer WIM in-place is the stall we hit: Saving image ~4% then wimserv CPU flatline.
& dism.exe /English /Unmount-Image /MountDir:$mountDir /Commit
if ($LASTEXITCODE -ne 0) { throw "DISM Unmount-Image failed: $LASTEXITCODE" }

if ($compression -eq 'max') {
    $exportTmp = Join-Path $mediaDir 'sources\install.export.wim'
    if (Test-Path -LiteralPath $exportTmp) { Remove-Item -LiteralPath $exportTmp -Force }
    Write-Host "DISM Export-Image /Compress:max → $exportTmp"
    # After Mount-InstallWim single-index export, the only image is index 1.
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
