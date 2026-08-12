#requires -Version 7.6
<#
.SYNOPSIS
  Pack a no-clone WinMint toolkit zip (Cli + Wizard + servicing + samples + apply harness).

.DESCRIPTION
  Publishes win-arm64 self-contained Cli/Wizard, AOT Provisioning, stages release layout,
  writes WinMint-<tag>.zip + WinMint-<tag>.zip.sha256 under -OutDir.
#>
param(
    [Parameter(Mandatory)]
    [string] $Tag,

    [string] $OutDir = '',

    [ValidateSet('win-arm64')]
    [string] $Runtime = 'win-arm64',

    [string] $Configuration = 'Release'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $repoRoot

$safeTag = $Tag.Trim()
if ([string]::IsNullOrWhiteSpace($safeTag)) {
    throw 'Tag is required (e.g. v0.1.0).'
}
if ($safeTag -notmatch '^[A-Za-z0-9._-]+$') {
    throw "Tag contains invalid characters: $safeTag"
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $repoRoot '.scratch\release'
}
elseif (-not [System.IO.Path]::IsPathRooted($OutDir)) {
    $OutDir = Join-Path $repoRoot $OutDir
}

$stageRoot = Join-Path $OutDir "WinMint-$safeTag"
$zipPath = Join-Path $OutDir "WinMint-$safeTag.zip"
$shaPath = "$zipPath.sha256"

if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null

$cliOut = Join-Path $stageRoot 'bin\cli'
$wizOut = Join-Path $stageRoot 'bin\wizard'
$provOut = Join-Path $stageRoot 'artifacts\provisioning'

Write-Host "Publishing Cli ($Runtime, self-contained)…"
dotnet publish (Join-Path $repoRoot 'src\WinMint.Cli\WinMint.Cli.csproj') `
    -c $Configuration -r $Runtime --self-contained true `
    -p:PublishSingleFile=false `
    -o $cliOut
if ($LASTEXITCODE -ne 0) { throw "Cli publish failed: $LASTEXITCODE" }

Write-Host "Publishing Wizard ($Runtime, self-contained)…"
dotnet publish (Join-Path $repoRoot 'src\WinMint.Wizard\WinMint.Wizard.csproj') `
    -c $Configuration -r $Runtime --self-contained true `
    -p:PublishSingleFile=false `
    -o $wizOut
if ($LASTEXITCODE -ne 0) { throw "Wizard publish failed: $LASTEXITCODE" }

Write-Host 'Publishing Provisioning Supervisor (AOT)…'
dotnet publish (Join-Path $repoRoot 'src\WinMint.Provisioning\WinMint.Provisioning.csproj') `
    -c $Configuration -o $provOut
if ($LASTEXITCODE -ne 0) { throw "Provisioning publish failed: $LASTEXITCODE" }

Copy-Item -LiteralPath (Join-Path $repoRoot 'Justfile') -Destination $stageRoot
Copy-Item -LiteralPath (Join-Path $repoRoot 'servicing') -Destination (Join-Path $stageRoot 'servicing') -Recurse
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot 'payload\scripts') | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'payload\scripts\SetupComplete.cmd') `
    -Destination (Join-Path $stageRoot 'payload\scripts\SetupComplete.cmd')
Copy-Item -LiteralPath (Join-Path $repoRoot 'samples') -Destination (Join-Path $stageRoot 'samples') -Recurse
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot 'tools\apply') | Out-Null
Copy-Item -Path (Join-Path $repoRoot 'tools\apply\*.ps1') -Destination (Join-Path $stageRoot 'tools\apply')
# Dot-sourced by tools\apply\*.ps1 as ..\Resolve-OutputIso.ps1
Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\Resolve-OutputIso.ps1') `
    -Destination (Join-Path $stageRoot 'tools\Resolve-OutputIso.ps1')
# Host helpers used by Justfile from toolkit root
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot 'tools\host') | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\host\Invoke-WinMintCli.ps1') `
    -Destination (Join-Path $stageRoot 'tools\host\Invoke-WinMintCli.ps1')
Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\host\Invoke-WinMintWizard.ps1') `
    -Destination (Join-Path $stageRoot 'tools\host\Invoke-WinMintWizard.ps1')

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipPath -Force

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $shaPath -Value "$hash  WinMint-$safeTag.zip" -Encoding ascii -NoNewline
Write-Host "Packed $zipPath"
Write-Host "SHA256 $hash → $shaPath"
