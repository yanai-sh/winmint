#requires -Version 7.6
<#
.SYNOPSIS
  Gate B wipe ISO: Release + package-strict Apply → apply assert (FU posture on Release).
.NOTES
  Workdir defaults to %LOCALAPPDATA%\WinMint\work\gate-b so TEMP toolkit cleanup cannot delete the Output ISO.
  # Must match HostDefaults.GateBWorkDirectory in WinMint.Orchestrator.
#>
param(
    # Required unless -AssertOnly (re-check existing Gate B workdir).
    [string] $Iso = '',

    [string] $Work = '',

    [string] $Profile = 'samples/sl7.profile.json',

    # 0 = resolve from host EditionID (Core→1 Home, Professional*→3 Pro). Override when calling PS directly.
    [ValidateRange(0, 32)]
    [int] $WimIndex = 0,

    [switch] $AssertOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\host\Get-WinMintDefaultWimIndex.ps1')

if ([string]::IsNullOrWhiteSpace($Work)) {
    . (Join-Path $PSScriptRoot '..\host\WinMintPaths.ps1')
    $Work = Get-WinMintGateBWorkDirectory
}

$hostApply = Join-Path $PSScriptRoot 'Invoke-HostApply.ps1'
if ($AssertOnly) {
    & $hostApply -AssertOnly -WorkDirectory $Work -ExpectDrivers -RequireLane Release
    exit $LASTEXITCODE
}

if ([string]::IsNullOrWhiteSpace($Iso)) {
    throw 'Iso is required unless -AssertOnly'
}

$resolvedWimIndex = if ($WimIndex -gt 0) { $WimIndex } else { Get-WinMintDefaultWimIndex }
Write-Host "Primary Gate WimIndex=$resolvedWimIndex (host edition default unless -WimIndex set)"

New-Item -ItemType Directory -Force -Path $Work | Out-Null
& $hostApply -Iso $Iso -Work $Work -Profile $Profile -ImageQuality Release -PackageStrict `
    -ExpectDrivers -RequireLane Release -AcceptanceKind GateB -WimIndex $resolvedWimIndex
exit $LASTEXITCODE
