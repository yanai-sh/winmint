#requires -Version 7.6
<#
.SYNOPSIS
  Publish and inventory the unsigned win-arm64 candidate surface.
  This is CI proof only; it never signs or creates a release asset.
#>
param(
    [string] $StageRoot = '.scratch\candidate\WinMint-v0.0.0',
    [string] $ProofRoot = '.scratch\candidate-proof'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location -LiteralPath $repoRoot

$stageFull = if ([IO.Path]::IsPathRooted($StageRoot)) { $StageRoot } else { Join-Path $repoRoot $StageRoot }
$proofFull = if ([IO.Path]::IsPathRooted($ProofRoot)) { $ProofRoot } else { Join-Path $repoRoot $ProofRoot }
if (Test-Path -LiteralPath $proofFull) { Remove-Item -LiteralPath $proofFull -Recurse -Force }
New-Item -ItemType Directory -Force -Path $proofFull | Out-Null

$logPath = Join-Path $proofFull 'candidate-build.log'
$transcriptStarted = $false
$tag = 'v0.0.0'
$hadTag = $false
$originalTagRef = $null
$originalTagCommit = $null
try {
    Start-Transcript -LiteralPath $logPath -Force | Out-Null
    $transcriptStarted = $true

    if (Test-Path -LiteralPath $stageFull) { Remove-Item -LiteralPath $stageFull -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stageFull | Out-Null

    $commit = (git rev-parse HEAD).Trim().ToLowerInvariant()
    if ($commit -notmatch '^[0-9a-f]{40}$') { throw "Unexpected HEAD commit: $commit" }

    # The release publisher deliberately requires a semver tag at HEAD. This local-only
    # placeholder gives candidate builds the same versioning and validation path.
    $originalTagRef = (git rev-parse "refs/tags/$tag" 2>$null).Trim().ToLowerInvariant()
    $originalTagCommit = (git rev-parse "refs/tags/$tag^{commit}" 2>$null).Trim().ToLowerInvariant()
    $hadTag = $originalTagRef -match '^[0-9a-f]{40}$' -and $originalTagCommit -match '^[0-9a-f]{40}$'
    git tag --force $tag HEAD | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not create candidate tag: $LASTEXITCODE" }

    & (Join-Path $repoRoot 'tools\release\Publish-WinMintRelease.ps1') `
        -Tag $tag -StageRoot $stageFull -Runtime win-arm64 -Configuration Release
    if ($LASTEXITCODE -ne 0) { throw "Candidate publish failed: $LASTEXITCODE" }

    $inventoryPath = Join-Path $proofFull 'candidate-inventory.json'
    $doc = & (Join-Path $repoRoot 'tools\release\Get-WinMintReleaseInventory.ps1') `
        -StageRoot $stageFull -Tag $tag -Phase Unsigned -OutFile $inventoryPath
    if ($doc.commit -cne $commit) { throw "Inventory commit does not match HEAD: $($doc.commit)" }
    if ($doc.tag -cne $tag) { throw "Inventory tag does not match candidate tag: $($doc.tag)" }
    if ($doc.phase -cne 'unsigned') { throw "Candidate inventory is not unsigned: $($doc.phase)" }
    $required = @(
        'bin/cli/WinMint.Cli.exe',
        'bin/wizard/WinMint.Wizard.exe',
        'artifacts/provisioning/WinMint.Provisioning.exe',
        'artifacts/winpe-apply/WinMintApply.exe'
    )
    $paths = @($doc.files | ForEach-Object path)
    foreach ($path in $required) {
        if ($path -notin $paths) { throw "Candidate inventory missing $path" }
    }
}
finally {
    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null }
        catch { Write-Warning "Could not stop candidate transcript: $($_.Exception.Message)" }
    }
    try {
        if ($hadTag) {
            git update-ref "refs/tags/$tag" $originalTagRef | Out-Null
        }
        else {
            git tag --delete $tag | Out-Null
        }
        if ($LASTEXITCODE -ne 0) { Write-Warning "Could not restore temporary candidate tag $tag (exit code $LASTEXITCODE)." }
    }
    catch {
        Write-Warning "Could not restore temporary candidate tag $tag`: $($_.Exception.Message)"
    }
}
