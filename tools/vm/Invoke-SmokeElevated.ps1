#requires -Version 7.6
<#
.SYNOPSIS
  Thin shim — prefer Start-SmokeElevated.ps1 (operator entry owns elevate/wt/transcript).

.EXAMPLE
  pwsh -NoProfile -File tools/vm/Start-SmokeElevated.ps1
#>
param(
    [string] $Work = '.scratch/smoke',
    [int] $WallClockMinutes = 180,
    [int] $StallMinutes = 45,
    [string] $Monitor = '1',
    [string] $OnlineOobe = '0',
    [string] $TranscriptPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$start = Join-Path $PSScriptRoot 'Start-SmokeElevated.ps1'
$splat = @{
    ElevatedWorker   = $true
    Work             = $Work
    WallClockMinutes = $WallClockMinutes
    StallMinutes     = $StallMinutes
    Monitor          = $Monitor
    OnlineOobe       = $OnlineOobe
}
if (-not [string]::IsNullOrWhiteSpace($TranscriptPath)) {
    $splat.TranscriptPath = $TranscriptPath
}
& $start @splat
exit $LASTEXITCODE
