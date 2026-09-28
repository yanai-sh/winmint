#requires -Version 7.6
<#
.SYNOPSIS
  Elevated maintainer Smoke (Apply + Hyper-V). Use when the shell is not admin.

.EXAMPLE
  sudo -E pwsh -NoProfile -File tools/vm/Invoke-SmokeElevated.ps1
  sudo -E pwsh -NoProfile -File tools/vm/Invoke-SmokeElevated.ps1 -Monitor 0
#>
param(
    [string] $Work = '.scratch/smoke',
    [int] $WallClockMinutes = 180,
    [int] $StallMinutes = 45,
    [string] $Monitor = '1',
    [string] $TranscriptPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    throw @"
Smoke needs an elevated pwsh (Apply + Hyper-V). From repo root:

  sudo -E pwsh -NoProfile -File tools/vm/Invoke-SmokeElevated.ps1

Or open an elevated terminal and run: just smoke-maintainer-monitor
"@
}

$log = if ([string]::IsNullOrWhiteSpace($TranscriptPath)) {
    Join-Path $repoRoot '.scratch\smoke\elevated-smoke.log'
}
else { $TranscriptPath }

New-Item -ItemType Directory -Force -Path (Split-Path $log -Parent) | Out-Null
Start-Transcript -LiteralPath $log -Force | Out-Null
try {
    Write-Host "Invoke-SmokeElevated Admin=True HEAD=$(git rev-parse --short HEAD)"
    $recipe = Join-Path $repoRoot 'tools\vm\Invoke-SmokeRecipe.ps1'
    & pwsh -NoProfile -File $recipe -Maintainer -Work $Work -WallClockMinutes $WallClockMinutes `
        -StallMinutes $StallMinutes -Monitor $Monitor
    exit $LASTEXITCODE
}
finally {
    Stop-Transcript | Out-Null
}
