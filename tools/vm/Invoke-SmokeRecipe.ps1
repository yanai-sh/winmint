#requires -Version 7.6
<#
.SYNOPSIS
  Entry point for `just smoke` and `just smoke-maintainer` (no nested just recipes).

.NOTES
  On Windows/PowerShell, `just smoke-maintainer WALL=180` binds WALL=180 to WORK positionally.
  Use positional overrides: `just smoke-maintainer .scratch/smoke 180 1 45`
  or `just smoke-maintainer-monitor` for Hyper-V Connect.
#>
param(
    [switch] $Maintainer,

    [string] $Iso = '',

    [string] $Work = '.scratch/smoke',

    [string] $ProfilePath = 'samples/sl7.profile.json',

    [int] $WallClockMinutes = 180,

    [int] $StallMinutes = 45,

    # 0/false/empty = headless; 1/true/yes = -Monitor (VMConnect).
    [string] $Monitor = '0',

    # 0/false/empty = offline OOBE (default); 1/true/yes = -OnlineOobe (NAT before Start-VM).
    [string] $OnlineOobe = '0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot

if ($Maintainer) {
    $fixturePath = Join-Path $repoRoot 'tests\fixtures\maintainer-host.json'
    $fixture = Get-Content -LiteralPath $fixturePath -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($Iso)) {
        $Iso = [string]$fixture.sourceIso.path
    }
    $ProfilePath = 'samples/sl7.profile.json'
}

if ([string]::IsNullOrWhiteSpace($Iso)) {
    throw 'Iso is required unless -Maintainer'
}

$useMonitor = $Monitor -in @('1', 'true', 'yes')
$useOnlineOobe = $OnlineOobe -in @('1', 'true', 'yes')
$smokeScript = Join-Path $repoRoot 'tools\vm\Invoke-Smoke.ps1'
$invokeArgs = @(
    '-NoProfile', '-NonInteractive', '-File', $smokeScript,
    '-Iso', $Iso,
    '-Work', $Work,
    '-ProfilePath', $ProfilePath,
    '-WallClockMinutes', $WallClockMinutes,
    '-StallMinutes', $StallMinutes
)
if ($useMonitor) { $invokeArgs += '-Monitor' }
if ($useOnlineOobe) { $invokeArgs += '-OnlineOobe' }

& pwsh @invokeArgs
exit $LASTEXITCODE
