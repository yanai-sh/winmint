#Requires -Version 7.3
<#
.SYNOPSIS
  Mounts a WinWS output ISO (read-only) and prints DISM-backed facts: install.wim images,
  architecture hint, layout checks, and optional manifest hash/size verification.

.DESCRIPTION
  Intended for an elevated PowerShell 7 session. Get-WindowsImage requires admin on typical
  Windows installs. Run from the repository root or any cwd; paths default to .\output\.

.EXAMPLE
  pwsh -NoProfile -File .\scripts\audit\Evaluate-OutputIso.ps1

.EXAMPLE
  pwsh -NoProfile -File .\scripts\audit\Evaluate-OutputIso.ps1 -IsoPath 'D:\builds\WinWS-20260101-120000.iso' -SkipHash
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot = '',
    [string]$IsoPath = '',
    [string]$ManifestPath = '',
    [switch]$SkipHash,
    [switch]$Json
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Test-WinWSElevation {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [Security.Principal.WindowsPrincipal]::new($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-WinWSRepositoryRoot {
    param([string]$Candidate)
    if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
        return (Resolve-Path -LiteralPath $Candidate).Path
    }
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}

function Get-WinWSNewestOutputIso {
    param([string]$OutDir)
    $iso = Get-ChildItem -LiteralPath $OutDir -Filter '*.iso' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    return $iso
}

if (-not (Test-WinWSElevation)) {
    Write-Error 'Run this script from an elevated PowerShell (Run as administrator). DISM image queries require elevation on this host.'
    exit 2
}

$repo = Resolve-WinWSRepositoryRoot -Candidate $RepositoryRoot
$outDir = Join-Path $repo 'output'

if ([string]::IsNullOrWhiteSpace($IsoPath)) {
    $isoItem = Get-WinWSNewestOutputIso -OutDir $outDir
    if (-not $isoItem) {
        Write-Error "No .iso files found under '$outDir'. Pass -IsoPath explicitly."
        exit 3
    }
    $IsoPath = $isoItem.FullName
}
else {
    if (-not (Test-Path -LiteralPath $IsoPath)) {
        Write-Error "ISO not found: $IsoPath"
        exit 3
    }
    $IsoPath = (Resolve-Path -LiteralPath $IsoPath).Path
}

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $defaultManifest = Join-Path $outDir 'WinWS-BuildManifest.json'
    $isoUnderOutput = $false
    try {
        $isoFull = [IO.Path]::GetFullPath($IsoPath)
        $outFull = [IO.Path]::GetFullPath($outDir)
        $sep = [IO.Path]::DirectorySeparatorChar
        $isoUnderOutput = $isoFull.StartsWith($outFull.TrimEnd($sep) + $sep, [StringComparison]::OrdinalIgnoreCase) -or
            ($isoFull.Equals($outFull, [StringComparison]::OrdinalIgnoreCase))
    }
    catch { }
    if ($isoUnderOutput -and (Test-Path -LiteralPath $defaultManifest)) {
        $ManifestPath = $defaultManifest
    }
}
elseif (-not (Test-Path -LiteralPath $ManifestPath)) {
    Write-Error "Manifest not found: $ManifestPath"
    exit 4
}
else {
    $ManifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path
}

Import-Module Dism -ErrorAction Stop
Import-Module Storage -ErrorAction Stop

$fileInfo = Get-Item -LiteralPath $IsoPath
$sha256 = $null
if (-not $SkipHash) {
    $sha256 = (Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256).Hash
}

$manifest = $null
$manifestOutput = $null
if ($ManifestPath) {
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    if ($manifest.PSObject.Properties['output']) {
        $manifestOutput = $manifest.output
    }
}

$report = [ordered]@{
    IsoPath            = $IsoPath
    FileSizeBytes      = [int64]$fileInfo.Length
    FileLastWriteTime  = [string]$fileInfo.LastWriteTimeUtc.ToString('o')
    Sha256             = [string]$sha256
    ManifestPath       = [string]$ManifestPath
    ManifestBuildResult = if ($manifest) { [string]$manifest.buildResult } else { '' }
    ManifestOutputIsoPath = if ($manifestOutput.isoPath) { [string]$manifestOutput.isoPath } else { '' }
    ManifestDeclaredSha256 = if ($manifestOutput.sha256) { [string]$manifestOutput.sha256 } else { '' }
    ManifestDeclaredSizeBytes = if ($null -ne $manifestOutput.sizeBytes) { [int64]$manifestOutput.sizeBytes } else { 0 }
    Sha256MatchesManifest = $false
    SizeMatchesManifest = $false
    MountedRoot        = ''
    InstallImagePath   = ''
    InstallImageCount  = 0
    InstallImages      = @()
    InstallArchitecture = ''
    BootWimPath        = ''
    BootWimImageCount  = 0
    HasSetupExe        = $false
    HasAutounattendXml = $false
    Error              = ''
}

if ($manifestOutput -and $sha256) {
    $report.Sha256MatchesManifest = ($sha256 -eq $manifestOutput.sha256)
}
if ($manifestOutput -and $null -ne $manifestOutput.sizeBytes) {
    $report.SizeMatchesManifest = ([int64]$fileInfo.Length -eq [int64]$manifestOutput.sizeBytes)
}

$mount = $null
try {
    $mount = Mount-DiskImage -ImagePath $IsoPath -Access ReadOnly -NoDriveLetter -PassThru -ErrorAction Stop
    $volume = $mount | Get-Volume -ErrorAction Stop | Select-Object -First 1
    if (-not $volume) { throw 'Mount succeeded but no volume was returned.' }

    $root = if ($volume.DriveLetter) {
        "$($volume.DriveLetter):\"
    }
    elseif ($volume.Path) {
        [string]$volume.Path
    }
    else {
        throw 'Mounted ISO did not expose a drive letter or volume path.'
    }
    $report.MountedRoot = $root

    $wim = Join-Path $root 'sources\install.wim'
    $esd = Join-Path $root 'sources\install.esd'
    if (Test-Path -LiteralPath $wim) {
        $report.InstallImagePath = $wim
    }
    elseif (Test-Path -LiteralPath $esd) {
        $report.InstallImagePath = $esd
    }
    else {
        throw 'Missing sources\install.wim and sources\install.esd.'
    }

    $images = @(Get-WindowsImage -ImagePath $report.InstallImagePath -ErrorAction Stop | Sort-Object ImageIndex)
    $report.InstallImageCount = $images.Count
    foreach ($img in $images) {
        $report.InstallImages += [ordered]@{
            ImageIndex = [int]$img.ImageIndex
            ImageName  = [string]$img.ImageName
            ImageSize  = if ($img.ImageSize) { [int64]$img.ImageSize } else { 0 }
        }
    }

    if ($images.Count -gt 0) {
        $first = Get-WindowsImage -ImagePath $report.InstallImagePath -Index ([int]$images[0].ImageIndex) -ErrorAction Stop
        $report.InstallArchitecture = switch ([int]$first.Architecture) {
            9 { 'amd64' }
            12 { 'arm64' }
            0 { 'x86' }
            default { "arch$([int]$first.Architecture)" }
        }
    }

    $bootWim = Join-Path $root 'sources\boot.wim'
    if (Test-Path -LiteralPath $bootWim) {
        $report.BootWimPath = $bootWim
        $report.BootWimImageCount = @(
            Get-WindowsImage -ImagePath $bootWim -ErrorAction SilentlyContinue
        ).Count
    }

    $report.HasSetupExe = Test-Path -LiteralPath (Join-Path $root 'setup.exe')
    $report.HasAutounattendXml = Test-Path -LiteralPath (Join-Path $root 'autounattend.xml')
}
catch {
    $report.Error = $_.Exception.Message
}
finally {
    if ($mount) {
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
    }
}

if ($report.Error) {
    if ($Json) {
        [pscustomobject]$report | ConvertTo-Json -Depth 8
    }
    else {
        Write-Host "Evaluation failed: $($report.Error)" -ForegroundColor Red
    }
    exit 1
}

if ($Json) {
    [pscustomobject]$report | ConvertTo-Json -Depth 8
    exit 0
}

Write-Host '=== WinWS output ISO evaluation ===' -ForegroundColor Cyan
Write-Host "ISO           : $($report.IsoPath)"
Write-Host "Size (bytes)  : $($report.FileSizeBytes)"
Write-Host "Modified (UTC): $($report.FileLastWriteTime)"
if ($sha256) {
    Write-Host "SHA256        : $sha256"
}
else {
    Write-Host 'SHA256        : (skipped; use -SkipHash:$false to compute)'
}

if ($ManifestPath) {
    Write-Host ''
    Write-Host "Manifest      : $ManifestPath"
    Write-Host "Build result  : $($report.ManifestBuildResult)"
    if ($manifestOutput.isoPath) {
        Write-Host "Manifest ISO  : $($report.ManifestOutputIsoPath)"
        $sameFile = ($report.ManifestOutputIsoPath -eq $report.IsoPath) -or
            ([string]::Equals(
                [IO.Path]::GetFullPath($report.ManifestOutputIsoPath),
                [IO.Path]::GetFullPath($report.IsoPath),
                [StringComparison]::OrdinalIgnoreCase))
        Write-Host "Same file     : $sameFile"
    }
    if ($sha256 -and $manifestOutput.sha256) {
        $color = if ($report.Sha256MatchesManifest) { 'Green' } else { 'Red' }
        Write-Host "SHA256 match  : $($report.Sha256MatchesManifest)" -ForegroundColor $color
    }
    if ($manifestOutput.sizeBytes) {
        $color = if ($report.SizeMatchesManifest) { 'Green' } else { 'Red' }
        Write-Host "Size match    : $($report.SizeMatchesManifest)" -ForegroundColor $color
    }
}

Write-Host ''
Write-Host "Mounted root  : $($report.MountedRoot)"
Write-Host "Install image : $($report.InstallImagePath)"
Write-Host "Architecture  : $($report.InstallArchitecture)"
Write-Host "Image count   : $($report.InstallImageCount)"
Write-Host 'Editions:'
foreach ($row in $report.InstallImages) {
    Write-Host ("  [{0}] {1}" -f $row.ImageIndex, $row.ImageName)
}

Write-Host ''
Write-Host "setup.exe      : $($report.HasSetupExe)"
Write-Host "autounattend   : $($report.HasAutounattendXml)"
if ($report.BootWimPath) {
    Write-Host "boot.wim       : $($report.BootWimPath) ($($report.BootWimImageCount) images)"
}
else {
    Write-Host 'boot.wim       : (missing)'
}

if ($manifest -and $manifest.PSObject.Properties['source']) {
    $src = $manifest.source
    $listed = @()
    if ($src.architecture) { $listed += "manifest source.architecture=$($src.architecture)" }
    if ($src.editions) {
        $listed += 'manifest source.editions:'
        foreach ($e in @($src.editions)) { $listed += "    $e" }
    }
    if ($listed.Count -gt 0) {
        Write-Host ''
        Write-Host '--- Cross-check (manifest vs WIM first image) ---' -ForegroundColor DarkGray
        Write-Host ($listed -join [Environment]::NewLine)
        if ($src.architecture -and $report.InstallArchitecture) {
            $archOk = [string]$src.architecture -eq [string]$report.InstallArchitecture
            Write-Host "Architecture string match: $archOk" -ForegroundColor $(if ($archOk) { 'Green' } else { 'Yellow' })
        }
    }
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Cyan
