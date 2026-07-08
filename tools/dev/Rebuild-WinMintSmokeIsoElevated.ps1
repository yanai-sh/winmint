#Requires -Version 7.6
#Requires -RunAsAdministrator
param(
    [string]$ProfilePath = 'tests\profiles\hyper-v-smoke-arm64.json',
    [switch]$FullImage
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot

$logPath = Join-Path $repoRoot ("output\rebuild-smoke-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $logPath) -Force

function Write-RebuildLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'o'), $Message
    Write-Host $line
    Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
}

Write-RebuildLog "Rebuild started: profile=$ProfilePath fullImage=$FullImage"
Write-RebuildLog 'Publishing native WinMintSetupShell (all arches)...'
& (Join-Path $repoRoot 'tools\release\Build-WinMintSetupShell.ps1') -AllArch *>&1 | ForEach-Object { Write-RebuildLog $_ }
if ($LASTEXITCODE -ne 0) { throw "Setup shell publish failed with exit code $LASTEXITCODE." }

$buildStartedAt = (Get-Date).AddSeconds(-5)
$cli = Join-Path $repoRoot 'WinMint-CLI.ps1'
$resolvedProfile = if ([IO.Path]::IsPathRooted($ProfilePath)) { $ProfilePath } else { Join-Path $repoRoot $ProfilePath }
Write-RebuildLog "Building ISO: $resolvedProfile"
if ($FullImage) {
    & $cli build $resolvedProfile -Yes *>&1 | ForEach-Object { Write-RebuildLog $_ }
}
else {
    & $cli build $resolvedProfile -Yes -FastImage *>&1 | ForEach-Object { Write-RebuildLog $_ }
}
if ($LASTEXITCODE -ne 0) { throw "WinMint build failed with exit code $LASTEXITCODE." }

$builtIso = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'output') -Filter 'WinMint-*.iso' -File |
    Where-Object { $_.LastWriteTime -ge $buildStartedAt } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $builtIso) {
    throw 'Build completed but no new WinMint-*.iso was found under output\.'
}

. (Join-Path $repoRoot 'tools\vm\WinMint-VmConsole.ps1')
$profileJson = Get-Content -LiteralPath $resolvedProfile -Raw | ConvertFrom-Json
$imageFp = Get-WinMintVmImageBuildFingerprint -ProfilePath $resolvedProfile -ProfileJson $profileJson -RepoRoot $repoRoot -Quality $(if ($FullImage) { 'max' } else { 'fast' })
$agentFp = Get-WinMintVmAgentBuildFingerprint -RepoRoot $repoRoot
$fingerprintPath = Join-Path $repoRoot 'output\.vm-build-fingerprint.json'
([ordered]@{
        fingerprint = $imageFp
        imageFingerprint = $imageFp
        agentFingerprint = $agentFp
        isoPath = $builtIso.FullName
        builtUtc = [datetime]::UtcNow.ToString('o')
    } | ConvertTo-Json) | Set-Content -LiteralPath $fingerprintPath -Encoding UTF8

Write-RebuildLog "Rebuild complete: $($builtIso.FullName) ($([Math]::Round($builtIso.Length / 1MB, 1)) MB)"
Write-RebuildLog "Fingerprint sidecar: $fingerprintPath"
