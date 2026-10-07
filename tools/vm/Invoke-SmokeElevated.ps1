#requires -Version 7.6
<#
.SYNOPSIS
  Elevated maintainer Smoke (Apply + Hyper-V). Use when the shell is not admin.

.EXAMPLE
  pwsh -NoProfile -File tools/vm/Start-SmokeElevated.ps1
  # Already elevated inside Windows Terminal:
  pwsh -NoProfile -File tools/vm/Invoke-SmokeElevated.ps1
#>
param(
    [string] $Work = '.scratch/smoke',
    [int] $WallClockMinutes = 180,
    [int] $StallMinutes = 45,
    [string] $Monitor = '1',
    # 0 = offline OOBE (default); 1 = online OOBE escape.
    [string] $OnlineOobe = '0',
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

  pwsh -NoProfile -File tools/vm/Start-SmokeElevated.ps1

Or: just smoke-maintainer-monitor
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
    # Same console — do not nest another pwsh.exe (that prefers conhost).
    & $recipe -Maintainer -Work $Work -WallClockMinutes $WallClockMinutes `
        -StallMinutes $StallMinutes -Monitor $Monitor -OnlineOobe $OnlineOobe
    exit $LASTEXITCODE
}
finally {
    Stop-Transcript | Out-Null
}
