#requires -Version 7.6
<#
.SYNOPSIS
  S5 Host Apply: real Apply on the build host → assert apply evidence. No Hyper-V, no bare-metal install.

.DESCRIPTION
  Runs elevated ImageServicing against a Source ISO offline WIM on this machine.
  Safe on the install-target laptop: does not wipe or boot from the output ISO.

  Modes:
    Full run (default): publish Supervisor, Apply, assert workdir evidence.
    -SkipApply: reuse existing workdir from a prior Apply.
    -AssertOnly: validate workdir only (no Apply).

.NOTES
  Requires: admin for Apply, network when Profile selects Surface Catalog drivers, user Source ISO.
#>
param(
    [Parameter(ParameterSetName = 'Run')]
    [string] $Iso,

    [Parameter(ParameterSetName = 'Run')]
    [string] $Work = (Join-Path (Get-Location) '.scratch\sl7-build'),

    [Parameter(ParameterSetName = 'Run')]
    [string] $Profile = 'samples/sl7.profile.json',

    [Parameter(ParameterSetName = 'Run')]
    [ValidateSet('Test', 'Release')]
    [string] $ImageQuality = 'Test',

    [Parameter(ParameterSetName = 'Run')]
    [switch] $PackageStrict,

    [Parameter(ParameterSetName = 'Run')]
    [switch] $SkipApply,

    [Parameter(Mandatory, ParameterSetName = 'AssertOnly')]
    [switch] $AssertOnly,

    [Parameter(ParameterSetName = 'AssertOnly')]
    [string] $WorkDirectory = '',

    [ValidateSet('Test', 'Release')]
    [string] $RequireLane = '',

    [ValidateSet('HostApply', 'GateB')]
    [string] $AcceptanceKind = 'HostApply',

    [switch] $ExpectDrivers,

    [switch] $ExpectNativePackageAuditJobs,

    [switch] $ExpectWingetImport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\Resolve-OutputIso.ps1')

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $repoRoot
. (Join-Path $repoRoot 'tools\AcceptanceManifest.ps1')

$assertScript = Join-Path $PSScriptRoot 'Assert-ApplyEvidence.ps1'

function Invoke-ApplyAssert {
    param(
        [string] $Dir,
        [string] $Lane = '',
        [switch] $Drivers,
        [switch] $NativeAuditJobs,
        [switch] $WingetImport
    )
    $assertParams = @{
        WorkDirectory    = $Dir
        RequireOutputIso = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($Lane)) { $assertParams['RequireLane'] = $Lane }
    if ($Drivers) { $assertParams['ExpectDrivers'] = $true }
    if ($NativeAuditJobs) { $assertParams['ExpectNativePackageAuditJobs'] = $true }
    if ($WingetImport) { $assertParams['ExpectWingetImport'] = $true }
    & $assertScript @assertParams
    if ($LASTEXITCODE -ne 0) { throw "Apply assert failed: $LASTEXITCODE" }
}

trap {
    $originalFailure = $_
    if (-not $AssertOnly -and -not $SkipApply -and -not [string]::IsNullOrWhiteSpace($Work)) {
        try {
            $failureLane = if (-not [string]::IsNullOrWhiteSpace($RequireLane)) { $RequireLane } else { $ImageQuality }
            $failureArtifacts = @(
                @('apply-status.txt', 'failure.json', 'evidence.json') |
                    Where-Object { Test-Path -LiteralPath (Join-Path $Work $_) -PathType Leaf }
            )
            if ($failureArtifacts.Count -eq 0) { $failureArtifacts = @('acceptance.manifest.json') }
            Write-WinMintAcceptanceManifest -Path (Join-Path $Work 'acceptance.manifest.json') `
                -AcceptanceKind $AcceptanceKind -Outcome failed -Lane $failureLane -RepositoryRoot $repoRoot `
                -SourceEvidenceSchemas @('winmint.image.evidence/v1') -ArtifactPaths $failureArtifacts `
                -PackageStrict ([Nullable[bool]]$PackageStrict) | Out-Null
        }
        catch {
            Write-Warning "Could not write failure acceptance manifest: $($_.Exception.Message)"
        }
    }
    throw $originalFailure
}

if ($AssertOnly) {
    $dir = if ([string]::IsNullOrWhiteSpace($WorkDirectory)) { $Work } else { $WorkDirectory }
    Invoke-ApplyAssert -Dir $dir -Lane $RequireLane -Drivers:$ExpectDrivers -NativeAuditJobs:$ExpectNativePackageAuditJobs -WingetImport:$ExpectWingetImport
    exit 0
}

# Gate B wipe media = Release + PackageStrict (just primary-gate). Soft Release Host Apply must not print flash guidance.
if ($ImageQuality -eq 'Release' -and -not $PackageStrict) {
    throw 'Release Host Apply without -PackageStrict is not Gate B. Use: just primary-gate ISO=...'
}

if ([string]::IsNullOrWhiteSpace($Iso)) {
    throw 'Iso is required for a full Host Apply run (user-supplied Source ISO).'
}
if (-not (Test-Path -LiteralPath $Iso)) {
    throw "Source ISO not found: $Iso"
}
if (-not (Test-Path -LiteralPath $Profile)) {
    throw "Profile not found: $Profile"
}

$expectDrivers = $ExpectDrivers
$expectNativeAuditJobs = $ExpectNativePackageAuditJobs
$expectWingetImport = $ExpectWingetImport
if (-not $expectDrivers) {
    try {
        $doc = Get-Content -LiteralPath $Profile -Raw -Encoding utf8 | ConvertFrom-Json
        $expectDrivers = $null -ne $doc.drivers -and -not [string]::IsNullOrWhiteSpace([string]$doc.drivers.deviceId)
    }
    catch {
        Write-Warning "Could not read Profile drivers block: $($_.Exception.Message)"
    }
}
try {
    if (-not (Get-Variable -Name doc -ErrorAction SilentlyContinue)) {
        $doc = Get-Content -LiteralPath $Profile -Raw -Encoding utf8 | ConvertFrom-Json
    }
    if ($null -ne $doc.packages -and $null -ne $doc.packages.winget) {
        $wingetIds = @($doc.packages.winget | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($wingetIds.Count -gt 0 -and -not $expectNativeAuditJobs) {
            $expectWingetImport = $true
        }
    }
}
catch {
    Write-Warning "Could not read Profile packages.winget: $($_.Exception.Message)"
}

function Resolve-WinMintCliExe {
    $published = Join-Path $repoRoot 'bin\cli\WinMint.Cli.exe'
    if (Test-Path -LiteralPath $published -PathType Leaf) {
        return $published
    }
    return $null
}

if (-not $SkipApply) {
    $supervisor = Join-Path $repoRoot 'artifacts\provisioning\WinMint.Provisioning.exe'
    if (-not (Test-Path -LiteralPath $supervisor -PathType Leaf)) {
        Write-Host 'Publishing Supervisor (Release AOT)…'
        & just publish-provisioning
        if ($LASTEXITCODE -ne 0) { throw "just publish-provisioning failed: $LASTEXITCODE" }
    }
    else {
        Write-Host "Using packaged Supervisor: $supervisor"
    }

    $strictArgs = @()
    if ($PackageStrict) { $strictArgs = @('--package-strict') }

    Write-Host "Host Apply Profile=$Profile Iso=$Iso Work=$Work Lane=$ImageQuality…"
    Write-Host 'Pre-wipe only: mutates offline WIM from Source ISO — does not install to this device.'
    $cliExe = Resolve-WinMintCliExe
    $buildArgs = @('build', $Profile, '--iso', $Iso, '--work', $Work, '--image-quality', $ImageQuality, '--package-audit-strict') + $strictArgs
    if ($cliExe) {
        & $cliExe @buildArgs
    }
    else {
        & dotnet run --project src/WinMint.Cli -- @buildArgs
    }
    if ($LASTEXITCODE -ne 0) { throw "Host Apply failed: $LASTEXITCODE" }
}

$assertLane = if (-not [string]::IsNullOrWhiteSpace($RequireLane)) { $RequireLane } else { $ImageQuality }
Invoke-ApplyAssert -Dir $Work -Lane $assertLane -Drivers:$expectDrivers -NativeAuditJobs:$expectNativeAuditJobs -WingetImport:$expectWingetImport

$sha = $null
$sourceSha = $null
$sourceLength = 0
$evidencePath = Join-Path $Work 'evidence.json'
$ev = $null
if (Test-Path -LiteralPath $evidencePath) {
    $ev = Get-Content -LiteralPath $evidencePath -Raw -Encoding utf8 | ConvertFrom-Json
    if ($ev.PSObject.Properties.Name -contains 'digests' -and $null -ne $ev.digests) {
        foreach ($p in $ev.digests.PSObject.Properties) {
            if ([string]$p.Name -eq 'outputIso.sha256') { $sha = [string]$p.Value }
            if ([string]$p.Name -eq 'source.isoSha256') { $sourceSha = [string]$p.Value }
            if ([string]$p.Name -eq 'source.isoLength') { $sourceLength = [long]$p.Value }
        }
    }
}
$outIso = Resolve-WinMintOutputIso -WorkDirectory $Work -Evidence $ev
if (-not $SkipApply) {
    $artifactRoot = (Resolve-Path $Work).Path
    $outputRelative = [IO.Path]::GetRelativePath($artifactRoot, (Resolve-Path $outIso).Path).Replace('\', '/')
    Write-WinMintAcceptanceManifest -Path (Join-Path $Work 'acceptance.manifest.json') `
        -AcceptanceKind $AcceptanceKind -Outcome green -Lane $assertLane -RepositoryRoot $repoRoot `
        -ProfilePath $Profile -SourceIsoPath $Iso -OutputIsoPath $outIso `
        -SourceIsoSha256 $sourceSha -SourceIsoLength $sourceLength -OutputIsoSha256 $sha `
        -SourceEvidenceSchemas @('winmint.image.evidence/v1', 'winmint.apply.acceptance/v1') `
        -ArtifactPaths @($outputRelative, 'evidence.json', 'apply-acceptance.json') `
        -PackageStrict ([Nullable[bool]]$PackageStrict)
}
Write-Host "Host Apply gate OK. Work=$Work lane=$assertLane"
if ($sha) { Write-Host "outputIso.sha256=$sha" }
if ($outIso) { Write-Host "Output ISO: $outIso" }
if ($assertLane -eq 'Release' -and $PackageStrict) {
    Write-Host "Flash only this workdir's Output ISO ($outIso). Do not flash a Test-lane workdir (.scratch/sl7-build)."
    Write-Host 'Next step (manual, destructive): write that ISO to USB and bare-metal install — not run by this harness.'
} else {
    Write-Host 'Test lane — not the Primary wipe ISO. Use just primary-gate for Release wipe media.'
}
exit 0
