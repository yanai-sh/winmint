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
    [switch] $SkipApply,

    [Parameter(Mandatory, ParameterSetName = 'AssertOnly')]
    [switch] $AssertOnly,

    [Parameter(ParameterSetName = 'AssertOnly')]
    [string] $WorkDirectory = '',

    [switch] $ExpectDrivers
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $repoRoot

$assertScript = Join-Path $PSScriptRoot 'Assert-MetalEvidence.ps1'

function Invoke-MetalAssert {
    param([string] $Dir, [switch] $Drivers)
    $args = @('-WorkDirectory', $Dir, '-RequireOutputIso')
    if ($Drivers) { $args += '-ExpectDrivers' }
    & $assertScript @args
    if ($LASTEXITCODE -ne 0) { throw "Metal assert failed: $LASTEXITCODE" }
}

if ($AssertOnly) {
    $dir = if ([string]::IsNullOrWhiteSpace($WorkDirectory)) { $Work } else { $WorkDirectory }
    Invoke-MetalAssert -Dir $dir -Drivers:$ExpectDrivers
    exit 0
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
if (-not $expectDrivers) {
    try {
        $doc = Get-Content -LiteralPath $Profile -Raw -Encoding utf8 | ConvertFrom-Json
        $expectDrivers = $null -ne $doc.drivers -and -not [string]::IsNullOrWhiteSpace([string]$doc.drivers.deviceId)
    }
    catch {
        Write-Warning "Could not read Profile drivers block: $($_.Exception.Message)"
    }
}

if (-not $SkipApply) {
    Write-Host 'Publishing Supervisor (Release AOT)…'
    & just publish-provisioning
    if ($LASTEXITCODE -ne 0) { throw "just publish-provisioning failed: $LASTEXITCODE" }

    Write-Host "Metal Apply Profile=$Profile Iso=$Iso Work=$Work Lane=$ImageQuality…"
    Write-Host 'Pre-wipe only: mutates offline WIM from Source ISO — does not install to this device.'
    & dotnet run --project src/WinMint.Cli -- build $Profile --iso $Iso --work $Work --image-quality $ImageQuality
    if ($LASTEXITCODE -ne 0) { throw "Metal Apply failed: $LASTEXITCODE" }
}

Invoke-MetalAssert -Dir $Work -Drivers:$expectDrivers
Write-Host "Metal gate OK. Work preserved: $Work"
Write-Host 'Next step (manual, destructive): write out.iso to USB and bare-metal install — not run by this harness.'
exit 0
