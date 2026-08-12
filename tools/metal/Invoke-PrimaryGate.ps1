#requires -Version 7.6
<#
.SYNOPSIS
  Gate B wipe ISO: Release + package-strict Apply → metal assert (FU posture on Release).
.NOTES
  Workdir defaults to %LOCALAPPDATA%\WinMint\work\sl7-primary so TEMP toolkit cleanup cannot delete the Output ISO.
  # Must match HostDefaults.GateBWorkDirectory in WinMint.Orchestrator.
#>
param(
    # Required unless -AssertOnly (re-check existing Gate B workdir).
    [string] $Iso = '',

    [string] $Work = '',

    [string] $Profile = 'samples/sl7.profile.json',

    [switch] $AssertOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Work)) {
    $Work = Join-Path $env:LOCALAPPDATA 'WinMint\work\sl7-primary'
}

$metal = Join-Path $PSScriptRoot 'Invoke-MetalApply.ps1'
if ($AssertOnly) {
    & $metal -AssertOnly -WorkDirectory $Work -ExpectDrivers -RequireLane Release
    exit $LASTEXITCODE
}

if ([string]::IsNullOrWhiteSpace($Iso)) {
    throw 'Iso is required unless -AssertOnly'
}

New-Item -ItemType Directory -Force -Path $Work | Out-Null
& $metal -Iso $Iso -Work $Work -Profile $Profile -ImageQuality Release -PackageStrict -ExpectDrivers -RequireLane Release
exit $LASTEXITCODE
