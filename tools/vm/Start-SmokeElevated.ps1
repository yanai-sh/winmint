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
. (Join-Path $repoRoot 'tools/host/Write-WinMintHostProgress.ps1')

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

    New-Item -ItemType Directory -Force -Path (Split-Path $log -Parent) | Out-Null
    Start-Transcript -LiteralPath $log -Force | Out-Null
    try {
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
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$inWt = -not [string]::IsNullOrWhiteSpace([string]$env:WT_SESSION)

# Already elevated inside Windows Terminal — stay in this tab.
if ($admin -and $inWt) {
    Invoke-WinMintSmokeElevatedWorker @workerSplat
    exit $LASTEXITCODE
}

$wt = Resolve-WinMintWindowsTerminal
$title = "WinMint smoke elevated — $Work"

function Start-WinMintArgvProcess {
    param(
        [Parameter(Mandatory)] [string] $FileName,
        [Parameter(Mandatory)] [string[]] $ArgumentList,
        [Parameter(Mandatory)] [string] $WorkingDirectory
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FileName
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    foreach ($a in $ArgumentList) { [void]$psi.ArgumentList.Add([string]$a) }
    [void][System.Diagnostics.Process]::Start($psi)
}

if ($admin -and $wt -and -not $inWt) {
    $wtArgs = @(
        '-w', '0', 'new-tab', '--title', $title, '-d', $repoRoot, '--',
        $pwshExe, '-NoProfile', '-File', $self
    ) + $innerArgs
    Start-WinMintArgvProcess -FileName $wt -ArgumentList $wtArgs -WorkingDirectory $repoRoot
    exit 0
}

if (-not $admin -and $wt) {
    $sudoArgs = @(
        '-E', $wt,
        '-w', '0', 'new-tab', '--title', $title, '-d', $repoRoot, '--',
        $pwshExe, '-NoProfile', '-File', $self
    ) + $innerArgs
    Start-WinMintArgvProcess -FileName 'sudo' -ArgumentList $sudoArgs -WorkingDirectory $repoRoot
    exit 0
}

if (-not $admin) {
    $sudoArgs = @('-E', $pwshExe, '-NoProfile', '-File', $self) + $innerArgs
    Start-WinMintArgvProcess -FileName 'sudo' -ArgumentList $sudoArgs -WorkingDirectory $repoRoot
    exit 0
}

# Elevated, no wt — run here (conhost).
Invoke-WinMintSmokeElevatedWorker @workerSplat
exit $LASTEXITCODE
