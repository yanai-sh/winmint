#Requires -Version 7.6
<#
.SYNOPSIS
    Native setup-shell integration: render self-test + optional interactive lifecycle.
#>
[CmdletBinding()]
param(
    [int]$SequenceDelayMs = 800,
    [switch]$SkipLaunch
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SetupShell.TestSupport.ps1')

$root = Get-WinMintTestRepoRoot -ScriptRoot $PSScriptRoot
$hostExe = Get-WinMintSetupShellExePath -Root $root
$nativeProgram = Get-Content -LiteralPath (Join-Path $root 'apps\setup-shell\Program.cs') -Raw
if ($nativeProgram -notmatch 'host=native') {
    throw 'Shipped setup shell host must be the native Direct2D entrypoint.'
}

$workspace = New-WinMintSetupShellTestWorkspace -Root $root
$capturePath = Join-Path $workspace.WorkDir 'render-self-test.png'
$renderProc = Start-Process `
    -FilePath $hostExe `
    -ArgumentList @(
        '--shell-root', $workspace.WorkDir,
        '--render-test',
        '--guest-capture', $capturePath,
        '--log'
    ) `
    -Wait `
    -PassThru `
    -NoNewWindow
if ($renderProc.ExitCode -ne 0) {
    throw "Native render self-test exited with code $($renderProc.ExitCode)."
}
if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf)) {
    throw "Native render self-test did not write capture: $capturePath"
}

Write-Host 'Native setup shell render self-test passed.'

if ($SkipLaunch) {
    return
}

$lifecycleWorkspace = New-WinMintSetupShellTestWorkspace -Root $root
$logDir = Join-Path $env:LOCALAPPDATA 'WinMint\Logs'
$null = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue

$proc = Start-WinMintSetupShellTestHost `
    -ExePath $hostExe `
    -WorkDir $lifecycleWorkspace.WorkDir `
    -StatusPath $lifecycleWorkspace.StatusPath `
    -ControlPath $lifecycleWorkspace.ControlPath `
    -Preview `
    -EnableLog

Start-Sleep -Milliseconds $SequenceDelayMs
Complete-WinMintSetupShellTestHost -Process $proc -ControlPath $lifecycleWorkspace.ControlPath -FailIfTimeout

$setupShellLog = Join-Path $logDir 'SetupShell.log'
if (-not (Test-Path -LiteralPath $setupShellLog)) {
    throw "Expected SetupShell.log at $setupShellLog"
}

$logText = Get-Content -LiteralPath $setupShellLog -Raw
if ($logText -notmatch 'host=native') {
    throw 'SetupShell.log missing host=native marker from the native setup shell host.'
}

Write-Host 'Native setup shell preview lifecycle passed.'