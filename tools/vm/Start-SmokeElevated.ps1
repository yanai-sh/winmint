#requires -Version 7.6
<#
.SYNOPSIS
  Start maintainer Smoke elevated, preferring a Windows Terminal window.

.DESCRIPTION
  `sudo -E pwsh -File Invoke-SmokeElevated.ps1` opens conhost. This entry
  elevates into `wt` when available so the admin host console matches Watch.

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
    [string] $TranscriptPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot
. (Join-Path $repoRoot 'tools/host/Write-WinMintHostProgress.ps1')

$elevated = Join-Path $repoRoot 'tools\vm\Invoke-SmokeElevated.ps1'
$pwshExe = (Get-Command pwsh.exe -ErrorAction Stop).Source
$innerArgs = @(
    '-Work', $Work,
    '-WallClockMinutes', "$WallClockMinutes",
    '-StallMinutes', "$StallMinutes",
    '-Monitor', "$Monitor",
    '-OnlineOobe', "$OnlineOobe"
)
if (-not [string]::IsNullOrWhiteSpace($TranscriptPath)) {
    $innerArgs += @('-TranscriptPath', $TranscriptPath)
}

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$inWt = -not [string]::IsNullOrWhiteSpace([string]$env:WT_SESSION)

# Already elevated inside Windows Terminal — stay in this tab.
if ($admin -and $inWt) {
    & $elevated @innerArgs
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
    # Elevated conhost → new elevated wt tab running the same elevated script.
    $wtArgs = @(
        '-w', '0', 'new-tab', '--title', $title, '-d', $repoRoot, '--',
        $pwshExe, '-NoProfile', '-File', $elevated
    ) + $innerArgs
    Start-WinMintArgvProcess -FileName $wt -ArgumentList $wtArgs -WorkingDirectory $repoRoot
    exit 0
}

if (-not $admin -and $wt) {
    # Unelevated → sudo elevates wt, then pwsh runs Invoke-SmokeElevated inside WT.
    $sudoArgs = @(
        '-E', $wt,
        '-w', '0', 'new-tab', '--title', $title, '-d', $repoRoot, '--',
        $pwshExe, '-NoProfile', '-File', $elevated
    ) + $innerArgs
    Start-WinMintArgvProcess -FileName 'sudo' -ArgumentList $sudoArgs -WorkingDirectory $repoRoot
    exit 0
}

if (-not $admin) {
    # No wt: legacy conhost elevate.
    $sudoArgs = @('-E', $pwshExe, '-NoProfile', '-File', $elevated) + $innerArgs
    Start-WinMintArgvProcess -FileName 'sudo' -ArgumentList $sudoArgs -WorkingDirectory $repoRoot
    exit 0
}

# Elevated, no wt — run here (conhost).
& $elevated @innerArgs
exit $LASTEXITCODE
