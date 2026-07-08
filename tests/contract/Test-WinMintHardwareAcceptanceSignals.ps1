#Requires -Version 7.6
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-HardwareSignalFailure {
    param([string]$Message)
    $script:failures.Add($Message) | Out-Null
}

. (Join-Path $root 'tools\acceptance\Test-WinMintHardwareAcceptanceSignals.ps1')

$machine = [pscustomobject]@{
    id = 'surface-laptop-7-arm64'
    requiredDriverPath = 'surface-laptop-7'
    signals = @(
        'firstLogon.ok', 'drivers.surfaceCatalog', 'drivers.firmwareExcluded', 'keep.edge',
        'agents.zenBrowser', 'agents.cursor', 'wsl.fedora', 'audit.zeroErrors',
        'desktop.noShellLayers', 'registry.gamingPerformanceBaseline', 'launcher.searchFallback'
    )
}

$passDir = Join-Path $root 'tests\fixtures\hardware-evidence\sl7-pass'
$passSignals = Test-WinMintHardwareAcceptanceSignals -EvidenceDir $passDir -Machine $machine
$passFailed = @($passSignals | Where-Object { -not $_.ok })
if ($passFailed.Count -gt 0) {
    Add-HardwareSignalFailure "sl7-pass fixture should pass all signals; failed: $($passFailed.id -join ', ')"
}

$failDir = Join-Path $root 'tests\fixtures\hardware-evidence\sl7-fail-missing-audit'
$failMachine = [pscustomobject]@{
    id = 'surface-laptop-7-arm64'
    requiredDriverPath = 'surface-laptop-7'
    signals = @('firstLogon.ok', 'audit.zeroErrors')
}
$failSignals = Test-WinMintHardwareAcceptanceSignals -EvidenceDir $failDir -Machine $failMachine
$auditSignal = @($failSignals | Where-Object { $_.id -eq 'audit.zeroErrors' } | Select-Object -First 1)
if ($auditSignal -and $auditSignal.ok) {
    Add-HardwareSignalFailure 'sl7-fail-missing-audit should fail audit.zeroErrors'
}
$firstLogonSignal = @($failSignals | Where-Object { $_.id -eq 'firstLogon.ok' } | Select-Object -First 1)
if ($firstLogonSignal -and $firstLogonSignal.ok) {
    Add-HardwareSignalFailure 'sl7-fail-missing-audit should fail firstLogon.ok'
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}
Write-Host 'Hardware acceptance signal contract: OK'
exit 0
