#requires -Version 7.6
param(
    [Parameter(Mandatory)] [string] $MountDir,
    [Parameter(Mandatory)] [string] $MediaDir,
    [Parameter(Mandatory)] [string] $WimOut,
    [Parameter(Mandatory)] [string] $WorkDirectory,
    [Parameter(Mandatory)] [string] $Lane,
    [Parameter(Mandatory)] [string] $Compression,
    [Parameter(Mandatory)] [string] $Cleanup
)
# Commit + unmount. Params from BuildPlan only — no Profile branching.
# Metadata assert + R/O clear + ei.cfg/PID.txt after final WIM shape.
. (Join-Path $PSScriptRoot 'Get-WimMetadata.ps1')
. (Join-Path $PSScriptRoot 'Resolve-WinMintMount.ps1')

$wimFile = Join-Path $mediaDir 'sources\install.wim'
if (-not (Test-Path -LiteralPath $wimFile)) { throw "install.wim missing: $wimFile" }

$before = Get-WimMetadataSnapshot -WimFile $wimFile -Index 1
if ([int]$before.IndexCount -ne 1) {
    throw "Refusing Unmount/Commit: install.wim has $($before.IndexCount) indexes (need 1). Mount-InstallWim must export a single-image WIM first."
}
Assert-WimMetadataPresent -Snapshot $before -Context 'ExportWim before commit'
Clear-WimReadOnly -WimFile $wimFile

if ($cleanup -eq 'full') {
    Write-Output "DISM Cleanup-Image /StartComponentCleanup /ResetBase ($mountDir)"
    & dism.exe /English /Image:$mountDir /Cleanup-Image /StartComponentCleanup /ResetBase
    if ($LASTEXITCODE -ne 0) { throw "DISM Cleanup-Image failed: $LASTEXITCODE" }
}
elseif ($cleanup -ne 'skip') {
    throw "unsupported cleanup='$cleanup' (expected skip|full)"
}

Write-Output "DISM Unmount-Image /Commit ($mountDir) lane=$lane compression=$compression cleanup=$cleanup name=$($before.Name)"
& dism.exe /English /Unmount-Image /MountDir:$mountDir /Commit
if ($LASTEXITCODE -ne 0) { throw "DISM Unmount-Image failed: $LASTEXITCODE" }
Remove-WinMintMountOwner -Kind install

$afterCommit = Get-WimMetadataSnapshot -WimFile $wimFile -Index 1
if ([int]$afterCommit.IndexCount -ne 1) {
    throw "After commit, install.wim has $($afterCommit.IndexCount) indexes (need 1)"
}
Assert-WimMetadataStable -Before $before -After $afterCommit -Context 'ExportWim after Unmount/Commit'

$final = $afterCommit
if ($compression -eq 'max') {
    Clear-WimReadOnly -WimFile $wimFile
    $exportTmp = Join-Path $mediaDir 'sources\install.export.wim'
    if (Test-Path -LiteralPath $exportTmp) { Remove-Item -LiteralPath $exportTmp -Force }
    Write-Output "DISM Export-Image /Compress:max → $exportTmp"
    & dism.exe /English /Export-Image /SourceImageFile:$wimFile /SourceIndex:1 /DestinationImageFile:$exportTmp /Compress:max
    if ($LASTEXITCODE -ne 0) { throw "DISM Export-Image failed: $LASTEXITCODE" }
    Remove-Item -LiteralPath $wimFile -Force
    Move-Item -LiteralPath $exportTmp -Destination $wimFile -Force
    Clear-WimReadOnly -WimFile $wimFile
    $afterMax = Get-WimMetadataSnapshot -WimFile $wimFile -Index 1
    if ([int]$afterMax.IndexCount -ne 1) {
        throw "After max export, install.wim has $($afterMax.IndexCount) indexes (need 1)"
    }
    Assert-WimMetadataStable -Before $afterCommit -After $afterMax -Context 'ExportWim after Compress:max'
    $final = $afterMax
}
elseif ($compression -ne 'fast') {
    throw "unsupported compression='$compression' (expected fast|max)"
}

Write-WinMintEditionConfig -MediaDir $mediaDir -Snapshot $final

if (Test-Path -LiteralPath $wimOut) { Remove-Item -LiteralPath $wimOut -Force }
New-Item -ItemType HardLink -Path $wimOut -Target $wimFile -ErrorAction SilentlyContinue | Out-Null
if (-not (Test-Path -LiteralPath $wimOut)) {
    Copy-Item -LiteralPath $wimFile -Destination $wimOut -Force
}

Write-WimMetadataEvidence -WorkDirectory $WorkDirectory -Document @{
    phase = 'ExportWim'; lane = $lane; compression = $compression; cleanup = $cleanup
    before = $before; afterCommit = $afterCommit; final = $final
}

Write-Output "ExportWim ok lane=$lane compression=$compression cleanup=$cleanup wimOut=$wimOut"
exit 0
