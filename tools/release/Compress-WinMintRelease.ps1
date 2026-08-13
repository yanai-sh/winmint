#requires -Version 7.6
<#
.SYNOPSIS
  Zip an already-staged WinMint toolkit tree. Never builds, restores, or rewrites staged files.
  If -StageRoot is omitted, runs Publish-WinMintRelease.ps1 first (unsigned staging only).
#>
param(
    [Parameter(Mandatory)] [string] $Tag,
    [string] $StageRoot = '',
    [string] $OutDir = '',
    [ValidateSet('win-arm64')] [string] $Runtime = 'win-arm64',
    [string] $Configuration = 'Release'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$safeTag = $Tag.Trim()
if ($safeTag -notmatch '^v\d+\.\d+\.\d+$') {
    throw "Tag must match vMAJOR.MINOR.PATCH: $Tag"
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $repoRoot '.scratch\release'
}
elseif (-not [System.IO.Path]::IsPathRooted($OutDir)) {
    $OutDir = Join-Path $repoRoot $OutDir
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if ([string]::IsNullOrWhiteSpace($StageRoot)) {
    $StageRoot = Join-Path $OutDir "WinMint-$safeTag"
    & (Join-Path $PSScriptRoot 'Publish-WinMintRelease.ps1') -Tag $safeTag -StageRoot $StageRoot -Runtime $Runtime -Configuration $Configuration
    if ($LASTEXITCODE -ne 0) { throw "Publish-WinMintRelease failed: $LASTEXITCODE" }
}
elseif (-not [System.IO.Path]::IsPathRooted($StageRoot)) {
    $StageRoot = Join-Path $repoRoot $StageRoot
}

if (-not (Test-Path -LiteralPath $StageRoot -PathType Container)) {
    throw "StageRoot missing: $StageRoot"
}

$zipPath = Join-Path $OutDir "WinMint-$safeTag.zip"
$shaPath = "$zipPath.sha256"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $StageRoot '*') -DestinationPath $zipPath -Force
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $shaPath -Value "$hash  WinMint-$safeTag.zip" -Encoding ascii -NoNewline
Write-Host "Packed $zipPath"
Write-Host "SHA256 $hash → $shaPath"
