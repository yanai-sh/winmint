#requires -Version 7.6
<#
.SYNOPSIS
  Operator entry for maintainer Smoke elevated (Windows Terminal when available).

.DESCRIPTION
  Owns elevate / wt / transcript / recipe forward. Invoke-SmokeElevated.ps1 is a thin
  shim for older call sites. Recipe stays the Just positional adapter; Invoke-Smoke is S4.

.EXAMPLE
  pwsh -NoProfile -File tools/vm/Start-SmokeElevated.ps1
  just smoke-maintainer-monitor
#>
param(
    [string] $Work = '.scratch/smoke',
    [int] $WallClockMinutes = 180,
    [int] $StallMinutes = 45,
    [string] $Monitor = '1',
    [string] $OnlineOobe = '0',
    [string] $TranscriptPath = '',
    # Reuse Work Output ISO (no Apply) — guest/chrome iteration.
    [switch] $SkipApply,
    # Private: already elevated process body (wt/sudo target). Not for operators.
    [switch] $ElevatedWorker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot
. (Join-Path $repoRoot 'tools/host/WinMintHostConsole.ps1')

function Invoke-WinMintSmokeElevatedWorker {
    param(
        [string] $Work,
        [int] $WallClockMinutes,
        [int] $StallMinutes,
        [string] $Monitor,
        [string] $OnlineOobe,
        [string] $TranscriptPath,
        [switch] $SkipApply
    )

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

    $workRoot = Get-WinMintHostConsoleWorkRoot -RepoRoot $repoRoot -Work $Work -TranscriptPath $TranscriptPath
    New-Item -ItemType Directory -Force -Path (Split-Path $log -Parent) | Out-Null
    Start-Transcript -LiteralPath $log -Force | Out-Null
    try {
        Write-WinMintHostConsoleWorkerPid -WorkRoot $workRoot
        Write-Host "Start-SmokeElevated Admin=True HEAD=$(git rev-parse --short HEAD)"
        $recipe = Join-Path $repoRoot 'tools\vm\Invoke-SmokeRecipe.ps1'
        # Same console — do not nest another pwsh.exe (that prefers conhost).
        $recipeSplat = @{
            Maintainer       = $true
            Work             = $Work
            WallClockMinutes = $WallClockMinutes
            StallMinutes     = $StallMinutes
            Monitor          = $Monitor
            OnlineOobe       = $OnlineOobe
        }
        if ($SkipApply) { $recipeSplat.SkipApply = $true }
        & $recipe @recipeSplat
        exit $LASTEXITCODE
    }
    finally {
        Clear-WinMintHostConsoleWorkerPid -WorkRoot $workRoot
        Stop-Transcript | Out-Null
    }
}

$workerSplat = @{
    Work             = $Work
    WallClockMinutes = $WallClockMinutes
    StallMinutes     = $StallMinutes
    Monitor          = $Monitor
    OnlineOobe       = $OnlineOobe
    TranscriptPath   = $TranscriptPath
    SkipApply        = $SkipApply
}

if ($ElevatedWorker) {
    Invoke-WinMintSmokeElevatedWorker @workerSplat
    exit $LASTEXITCODE
}

# String argv for ProcessStartInfo / sudo / wt.
$innerArgs = @(
    '-ElevatedWorker',
    '-Work', $Work,
    '-WallClockMinutes', "$WallClockMinutes",
    '-StallMinutes', "$StallMinutes",
    '-Monitor', "$Monitor",
    '-OnlineOobe', "$OnlineOobe"
)
if ($SkipApply) { $innerArgs += '-SkipApply' }
if (-not [string]::IsNullOrWhiteSpace($TranscriptPath)) {
    $innerArgs += @('-TranscriptPath', $TranscriptPath)
}

$self = Join-Path $repoRoot 'tools\vm\Start-SmokeElevated.ps1'
$pwshExe = (Get-Command pwsh.exe -ErrorAction Stop).Source

$elevSplat = @{
    Elevate        = $true
    RepoRoot       = $repoRoot
    Work           = $Work
    File           = $self
    ArgumentList   = $innerArgs
    PwshExe        = $pwshExe
    TranscriptPath = $TranscriptPath
}
$result = Start-WinMintHostConsole @elevSplat

if ($result.disposition -eq 'RunHere') {
    Invoke-WinMintSmokeElevatedWorker @workerSplat
    exit $LASTEXITCODE
}

# Spawned — wait for elevated worker pid file (sidecar childPid is wt/sudo; exits in ms).
# ponytail: Stopwatch poll; no named-WT kill helper (ceiling: would kill other tabs in that window).
$workRoot = Get-WinMintHostConsoleWorkRoot -RepoRoot $repoRoot -Work $Work -TranscriptPath $TranscriptPath
$alive = [Diagnostics.Stopwatch]::StartNew()
while ($alive.Elapsed.TotalSeconds -lt 8) {
    if (Test-WinMintHostConsoleWorkerPidAlive -WorkRoot $workRoot) {
        exit 0
    }
    Start-Sleep -Milliseconds 150
}

throw "childExitedEarly: workerPidFile=$(Get-WinMintHostConsoleWorkerPidPath -WorkRoot $workRoot) launcherPid=$($result.childPid)"
