#requires -Version 7.6
<#
.SYNOPSIS
  S5 Metal: real Apply on the build host → assert apply evidence. No Hyper-V, no bare-metal install.

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

    [switch] $ExpectDrivers,

    [switch] $ExpectNativePackageAuditJobs,

    [switch] $ExpectWingetImport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $repoRoot

$assertScript = Join-Path $PSScriptRoot 'Assert-MetalEvidence.ps1'

function Invoke-MetalAssert {
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
    if ($LASTEXITCODE -ne 0) { throw "Metal assert failed: $LASTEXITCODE" }
}

if ($AssertOnly) {
    $dir = if ([string]::IsNullOrWhiteSpace($WorkDirectory)) { $Work } else { $WorkDirectory }
    Invoke-MetalAssert -Dir $dir -Lane $RequireLane -Drivers:$ExpectDrivers -NativeAuditJobs:$ExpectNativePackageAuditJobs -WingetImport:$ExpectWingetImport
    exit 0
}

# Gate B wipe media = Release + PackageStrict (just primary-gate). Soft Release metal must not print flash guidance.
if ($ImageQuality -eq 'Release' -and -not $PackageStrict) {
    throw 'Release metal without -PackageStrict is not Gate B. Use: just primary-gate ISO=...'
}

if ([string]::IsNullOrWhiteSpace($Iso)) {
    throw 'Iso is required for a full Metal Apply run (user-supplied Source ISO).'
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

    $reuseArgs = @()
    $marker = Join-Path $Work 'media\sources\.winmint-single-index'
    if (Test-Path -LiteralPath $marker) {
        Write-Host 'Found single-image marker — passing --reuse-media'
        $reuseArgs = @('--reuse-media')
    }

    $strictArgs = @()
    if ($PackageStrict) { $strictArgs = @('--package-strict') }

    Write-Host "Metal Apply Profile=$Profile Iso=$Iso Work=$Work Lane=$ImageQuality…"
    Write-Host 'Pre-wipe only: mutates offline WIM from Source ISO — does not install to this device.'
    $cliExe = Resolve-WinMintCliExe
    $buildArgs = @('build', $Profile, '--iso', $Iso, '--work', $Work, '--image-quality', $ImageQuality, '--package-audit-strict') + $strictArgs + $reuseArgs
    if ($cliExe) {
        & $cliExe @buildArgs
    }
    else {
        & dotnet run --project src/WinMint.Cli -- @buildArgs
    }
    if ($LASTEXITCODE -ne 0) { throw "Metal Apply failed: $LASTEXITCODE" }
}

$assertLane = if (-not [string]::IsNullOrWhiteSpace($RequireLane)) { $RequireLane } else { $ImageQuality }
Invoke-MetalAssert -Dir $Work -Lane $assertLane -Drivers:$expectDrivers -NativeAuditJobs:$expectNativeAuditJobs -WingetImport:$expectWingetImport

$outIso = Join-Path $Work 'out.iso'
$sha = $null
$evidencePath = Join-Path $Work 'evidence.json'
if (Test-Path -LiteralPath $evidencePath) {
    $ev = Get-Content -LiteralPath $evidencePath -Raw -Encoding utf8 | ConvertFrom-Json
    if ($ev.PSObject.Properties.Name -contains 'digests' -and $null -ne $ev.digests) {
        foreach ($p in $ev.digests.PSObject.Properties) {
            if ([string]$p.Name -eq 'outputIso.sha256') { $sha = [string]$p.Value; break }
        }
    }
}
Write-Host "Metal gate OK. Work=$Work lane=$assertLane"
if ($sha) { Write-Host "outputIso.sha256=$sha" }
if ($assertLane -eq 'Release' -and $PackageStrict) {
    Write-Host "Flash only this workdir's out.iso ($outIso). Do not flash a Test metal workdir (.scratch/sl7-build)."
} else {
    Write-Host 'Test lane — not the Primary wipe ISO. Use just primary-gate for Release wipe media.'
}
Write-Host 'Next step (manual, destructive): write out.iso to USB and bare-metal install — not run by this harness.'
exit 0
