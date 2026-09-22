#requires -Version 7.6
Set-StrictMode -Version Latest
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$bloom = Join-Path $repo 'payload\media\wallpaper\bloom.jpg'
if (-not (Test-Path -LiteralPath $bloom -PathType Leaf)) { throw "bloom.jpg missing: $bloom" }
if ((Get-Item -LiteralPath $bloom).Length -lt 1KB) { throw 'bloom.jpg too small' }
foreach ($font in @('CascadiaCodeNF.ttf', 'CascadiaMonoNF.ttf')) {
    $path = Join-Path $repo (Join-Path 'payload\fonts' $font)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "font missing: $path" }
    if ((Get-Item -LiteralPath $path).Length -lt 1KB) { throw "$font too small" }
}
$stage = Get-Content -LiteralPath (Join-Path $repo 'servicing\Stage-Payload.ps1') -Raw
if ($stage -notmatch 'WinMint-Bloom\.jpg') { throw 'Stage-Payload.ps1 must copy WinMint-Bloom.jpg' }
if ($stage -notmatch 'LayoutModification\.xml') { throw 'Stage-Payload.ps1 must copy LayoutModification.xml' }
if ($stage -notmatch 'TaskbarLayoutModification\.xml') { throw 'Stage-Payload.ps1 must copy OEM TaskbarLayoutModification.xml' }
if ($stage -match 'OneDriveSetup\.exe') { throw 'Stage-Payload.ps1 must not delete OneDriveSetup.exe' }
if ($stage -match 'OneDrive\.lnk') { throw 'Stage-Payload.ps1 must not delete Default OneDrive.lnk' }
if ($stage -match 'Set-ReservedStorageState') { throw 'Stage-Payload.ps1 must not use unsupported DISM /Image Reserved Storage' }
if ($stage -notmatch 'Users\\Default\\Documents\\PowerShell') { throw 'Stage-Payload.ps1 must copy Default profile skel' }
if ($stage -notmatch 'CascadiaCodeNF\.ttf') { throw 'Stage-Payload.ps1 must copy Cascadia fonts' }
