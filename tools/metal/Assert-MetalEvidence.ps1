#requires -Version 7.6
<#
.SYNOPSIS
  Assert ImageServicing Apply workdir evidence (S5 Metal). Pure — no Apply, no Hyper-V, no install.

.DESCRIPTION
  Pre-wipe gate: validates offline build output on the physical build host before any USB/destructive install.

  Expects under -WorkDirectory:
    evidence.json              (winmint.image.evidence/v1)
    logs/WinMint-DriverInventory.json   (when -ExpectDrivers)
    out.iso                    (optional when -RequireOutputIso)

  Writes metal-acceptance.json on success.
.NOTES
  Does not boot, mount USB, or modify the running OS — Apply mutates an offline WIM from Source ISO only.
#>
param(
    [Parameter(Mandatory)]
    [string] $WorkDirectory,

    [switch] $ExpectDrivers,

    [int] $MinimumIncludedDrivers = 1,

    [switch] $RequireOutputIso,

    [switch] $ExpectNativePackageAuditJobs,

    [switch] $ExpectWingetImport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $WorkDirectory)) {
    throw "Work directory missing: $WorkDirectory"
}

$evidencePath = Join-Path $WorkDirectory 'evidence.json'
if (-not (Test-Path -LiteralPath $evidencePath)) {
    throw "Apply evidence.json missing: $evidencePath"
}

$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding utf8 | ConvertFrom-Json
if ([string]$evidence.schemaVersion -ne 'winmint.image.evidence/v1') {
    throw "unexpected evidence schema '$($evidence.schemaVersion)'"
}

$lane = $null
if ($evidence.PSObject.Properties.Name -contains 'lane' -and $evidence.lane) {
    $lane = [string]$evidence.lane
}
if (-not $lane) {
    throw 'lane marker missing (evidence.json must include lane)'
}
if ($lane -notin @('Test', 'Release')) {
    throw "lane marker must be Test|Release, got '$lane'"
}

$digestMap = @{}
if ($evidence.PSObject.Properties.Name -contains 'digests' -and $null -ne $evidence.digests) {
    foreach ($p in $evidence.digests.PSObject.Properties) {
        $digestMap[[string]$p.Name] = [string]$p.Value
    }
}

if ($RequireOutputIso) {
    $outIso = Join-Path $WorkDirectory 'out.iso'
    if (-not (Test-Path -LiteralPath $outIso)) {
        throw "Output ISO missing: $outIso"
    }
    if ($digestMap.ContainsKey('outputIso.sha256') -and [string]::IsNullOrWhiteSpace($digestMap['outputIso.sha256'])) {
        throw 'outputIso.sha256 digest empty'
    }
}

$inventoryPath = Join-Path $WorkDirectory 'logs\WinMint-DriverInventory.json'
$driverIncluded = $null
$driverExcluded = $null
$firmwareExcluded = $null

if ($ExpectDrivers) {
    if (-not (Test-Path -LiteralPath $inventoryPath)) {
        throw "Driver inventory missing: $inventoryPath (ExpectDrivers)"
    }
    $inventory = Get-Content -LiteralPath $inventoryPath -Raw -Encoding utf8 | ConvertFrom-Json
    $driverIncluded = [int]$inventory.includedOfflineCount
    $driverExcluded = [int]$inventory.excludedCount
    if ($driverIncluded -lt $MinimumIncludedDrivers) {
        throw "Driver inventory includedOfflineCount=$driverIncluded (need >= $MinimumIncludedDrivers)"
    }

    $firmwareRows = @($inventory.records | Where-Object {
            [string]$_.class -eq 'firmware' -and [string]$_.decision -eq 'includeOffline'
        })
    if ($firmwareRows.Count -gt 0) {
        throw 'Driver inventory must not include firmware-class drivers offline'
    }
    $firmwareExcluded = $true

    foreach ($key in @('drivers.deviceId', 'drivers.includedCount', 'drivers.excludedCount')) {
        if (-not $digestMap.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($digestMap[$key])) {
            throw "Driver digest missing in evidence.json: $key"
        }
    }
    if ($digestMap.ContainsKey('drivers.firmwareExcluded') -and
        $digestMap['drivers.firmwareExcluded'] -notin @('True', 'true', '1')) {
        throw "drivers.firmwareExcluded must be true, got '$($digestMap['drivers.firmwareExcluded'])'"
    }

    if (-not $digestMap.ContainsKey('policy.deviceInstaller.DisableCoInstallers')) {
        throw 'DisableCoInstallers policy digest missing (policy.deviceInstaller.DisableCoInstallers)'
    }
    if ($digestMap['policy.deviceInstaller.DisableCoInstallers'] -ne '1') {
        throw "DisableCoInstallers expected 1, got '$($digestMap['policy.deviceInstaller.DisableCoInstallers'])'"
    }
}

if ($ExpectNativePackageAuditJobs) {
    $jobsPath = Join-Path $WorkDirectory 'payload\jobs.json'
    if (-not (Test-Path -LiteralPath $jobsPath)) {
        throw "payload/jobs.json missing: $jobsPath (ExpectNativePackageAuditJobs)"
    }
    $jobsDoc = Get-Content -LiteralPath $jobsPath -Raw -Encoding utf8 | ConvertFrom-Json
    $auditJobs = @($jobsDoc.jobs | Where-Object { [string]$_.kind -eq 'package.auditNative' })
    if ($auditJobs.Count -eq 0) {
        throw 'payload/jobs.json must include package.auditNative when -ExpectNativePackageAuditJobs'
    }
}

if ($ExpectWingetImport) {
    $importPath = Join-Path $WorkDirectory 'payload\winget-import.json'
    if (-not (Test-Path -LiteralPath $importPath)) {
        throw "payload/winget-import.json missing: $importPath (ExpectWingetImport)"
    }
    $importDoc = Get-Content -LiteralPath $importPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ($null -eq $importDoc.Sources -or @($importDoc.Sources).Count -eq 0) {
        throw 'winget-import.json must include Sources[]'
    }
    $jobsPath = Join-Path $WorkDirectory 'payload\jobs.json'
    if (-not (Test-Path -LiteralPath $jobsPath)) {
        throw "payload/jobs.json missing: $jobsPath (ExpectWingetImport)"
    }
    $jobsDoc = Get-Content -LiteralPath $jobsPath -Raw -Encoding utf8 | ConvertFrom-Json
    $importJobs = @($jobsDoc.jobs | Where-Object { [string]$_.kind -eq 'winget.import' })
    if ($importJobs.Count -eq 0) {
        throw 'payload/jobs.json must include winget.import when -ExpectWingetImport'
    }
}

$acceptance = [ordered]@{
    schemaVersion = 'winmint.metal.acceptance/v1'
    lane          = $lane
    preWipeOnly   = $true
}
if ($null -ne $driverIncluded) {
    $acceptance.driverIncludedCount = $driverIncluded
    $acceptance.driverExcludedCount = $driverExcluded
    $acceptance.firmwareExcluded = $firmwareExcluded
}

$acceptancePath = Join-Path $WorkDirectory 'metal-acceptance.json'
$acceptance | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $acceptancePath -Encoding utf8
Write-Output "Metal acceptance OK (lane=$lane pre-wipe-only)"
exit 0
