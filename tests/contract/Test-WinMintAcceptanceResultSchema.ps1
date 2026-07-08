#Requires -Version 7.6
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-AcceptanceFailure {
    param([string]$Message)
    $script:failures.Add($Message) | Out-Null
}

. (Join-Path $root 'tools\acceptance\New-WinMintAcceptanceResult.ps1')

$requiredTop = @('schemaVersion', 'verdict', 'plumbingVerdict', 'evidenceVerdict', 'signalChecks', 'startedAt', 'evidenceDir')
$hardwareFixture = Join-Path $root 'tests\fixtures\hardware-evidence\sl7-pass\acceptance-result.json'
if (-not (Test-Path -LiteralPath $hardwareFixture)) {
    $machine = [pscustomobject]@{
        id = 'surface-laptop-7-arm64'
        requiredDriverPath = 'surface-laptop-7'
        signals = @(
            'firstLogon.ok', 'drivers.surfaceCatalog', 'drivers.firmwareExcluded', 'keep.edge',
            'agents.zenBrowser', 'agents.cursor', 'wsl.fedora', 'audit.zeroErrors',
            'desktop.noShellLayers', 'registry.gamingPerformanceBaseline', 'launcher.searchFallback'
        )
    }
    $evidenceDir = Join-Path $root 'tests\fixtures\hardware-evidence\sl7-pass'
    . (Join-Path $root 'tools\acceptance\Test-WinMintHardwareAcceptanceSignals.ps1')
    $signals = Test-WinMintHardwareAcceptanceSignals -EvidenceDir $evidenceDir -Machine $machine
    $result = Complete-WinMintAcceptanceResult -Result ([ordered]@{
            acceptanceMode = 'hardware'
            machineId = 'surface-laptop-7-arm64'
            acceptanceTier = 'Hardware'
            startedAt = (Get-Date).ToString('o')
            evidenceDir = $evidenceDir
            reachable = $true
            firstLogon = @{ status = 'ok' }
        }) -Signals $signals -AcceptanceTier Hardware
    Write-WinMintAcceptanceResult -Result $result -Path $hardwareFixture
}

$payload = Get-Content -LiteralPath $hardwareFixture -Raw | ConvertFrom-Json
foreach ($name in $requiredTop) {
    if (-not $payload.PSObject.Properties[$name]) {
        Add-AcceptanceFailure "hardware fixture missing required field '$name'"
    }
}
if ([int]$payload.schemaVersion -ne 1) {
    Add-AcceptanceFailure 'hardware fixture schemaVersion must be 1'
}
if ($payload.verdict -ne 'pass') {
    Add-AcceptanceFailure "expected sl7-pass fixture verdict pass; got $($payload.verdict)"
}
if (-not $payload.signalChecks.signals -or @($payload.signalChecks.signals).Count -lt 5) {
    Add-AcceptanceFailure 'hardware fixture must include signalChecks.signals'
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}
Write-Host 'Acceptance result schema contract: OK'
exit 0
