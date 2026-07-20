#Requires -Version 7.6
<#
.SYNOPSIS
    VM acceptance must use dual-channel Spectre/verbose build logging (777a722),
    not the old [SUB] stdout pipe wrap for the ISO build phase. Managed start
    opens one live worker console (not separate verbose/run.log tail tabs).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-SpectreChannelFailure {
    param([string]$Message)
    $script:failures.Add($Message) | Out-Null
}

$acceptance = Get-Content -LiteralPath (Join-Path $root 'tools\vm\Invoke-WinMintVmAcceptance.ps1') -Raw
$managed = Get-Content -LiteralPath (Join-Path $root 'tools\vm\Start-WinMintVmAcceptanceManaged.ps1') -Raw
$vmLog = Get-Content -LiteralPath (Join-Path $root 'tools\vm\lib\VmLog.ps1') -Raw
$vmObserve = Get-Content -LiteralPath (Join-Path $root 'tools\vm\lib\VmObserve.ps1') -Raw

if ($acceptance -notmatch 'Invoke-WinMintVmSpectreBuildCommand') {
    Add-SpectreChannelFailure 'Invoke-WinMintVmAcceptance.ps1 must run the build via Invoke-WinMintVmSpectreBuildCommand.'
}
if ($acceptance -match 'Invoke-WinMintVmLoggedCommand[\s\S]{0,120}Build-And-TestVm') {
    Add-SpectreChannelFailure 'Build/boot must not go through Invoke-WinMintVmLoggedCommand ([SUB] pipe kills Spectre).'
}
if ($vmLog -notmatch 'function Invoke-WinMintVmSpectreBuildCommand') {
    Add-SpectreChannelFailure 'VmLog.ps1 must define Invoke-WinMintVmSpectreBuildCommand.'
}
if ($vmLog -notmatch 'function Initialize-WinMintVmHumanConsole') {
    Add-SpectreChannelFailure 'VmLog.ps1 must initialize Spectre chrome for harness Wait/Inspect lines.'
}
if ($vmObserve -notmatch 'function Start-WinMintVmAcceptanceWorkerConsole') {
    Add-SpectreChannelFailure 'VmObserve.ps1 must define Start-WinMintVmAcceptanceWorkerConsole (single live session).'
}
if ($managed -notmatch 'Start-WinMintVmAcceptanceWorkerConsole') {
    Add-SpectreChannelFailure 'Managed starter must launch the worker via Start-WinMintVmAcceptanceWorkerConsole.'
}
if ($managed -match 'Start-WinMintVmBuildLogViewersInWindowsTerminal') {
    Add-SpectreChannelFailure 'Managed starter must not open dual verbose/run.log tail tabs (live worker console is enough).'
}
if ($managed -notmatch 'WinMint-Build\.verbose\.log' -and $managed -notmatch 'Get-WinMintVmBuildVerboseLogPath') {
    Add-SpectreChannelFailure 'Managed starter must still record WinMint-Build.verbose.log path in the handle.'
}
if ($managed -match 'RedirectStandardOutput\s+\$runLog') {
    Add-SpectreChannelFailure 'Managed worker must not RedirectStandardOutput to run.log (flattens Spectre).'
}
if ($managed -notmatch 'NoLogViewer') {
    Add-SpectreChannelFailure 'Managed starter must keep -NoLogViewer as the headless (no live console) opt-out.'
}
if ($vmObserve -notmatch 'WindowId -1' -and $vmObserve -notmatch 'WindowId\s*=\s*-1') {
    Add-SpectreChannelFailure 'Managed worker Windows Terminal launch should use a new window (-w -1).'
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}

Write-Host 'VM Spectre build channels contract: OK'
exit 0
