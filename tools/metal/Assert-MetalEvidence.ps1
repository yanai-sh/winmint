#requires -Version 7.6
<#
.SYNOPSIS
  Assert ImageServicing Apply workdir evidence (S5 Metal). Pure — no Apply, no Hyper-V, no install.

.DESCRIPTION
  Pre-wipe gate: validates offline build output on the physical build host before any USB/destructive install.

  Expects under -WorkDirectory:
    evidence.json              (winmint.image.evidence/v1)
    logs/WinMint-DriverInventory.json   (when -ExpectDrivers)
    out.iso / winmint_*.iso   (optional when -RequireOutputIso; prefer evidence.outputIsoPath)

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

    [switch] $ExpectWingetImport,

    # When set (e.g. wipe assert), evidence.lane must match — blocks greening a Test tree as Primary.
    [ValidateSet('Test', 'Release')]
    [string] $RequireLane = '',

    # FU-durable offline posture (ADR-009). Defaults on when -RequireLane Release.
    [switch] $ExpectFuPosture
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-WinMintOutputIso {
    param(
        [Parameter(Mandatory)][string] $WorkDirectory,
        $Evidence = $null
    )
    if ($null -ne $Evidence -and $Evidence.PSObject.Properties.Name -contains 'outputIsoPath') {
        $claimed = [string]$Evidence.outputIsoPath
        if (-not [string]::IsNullOrWhiteSpace($claimed) -and (Test-Path -LiteralPath $claimed)) {
            return (Resolve-Path -LiteralPath $claimed).Path
        }
    }
    $named = @(Get-ChildItem -LiteralPath $WorkDirectory -Filter 'winmint_*.iso' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    if ($named.Count -ge 1) {
        return $named[0].FullName
    }
    $legacy = Join-Path $WorkDirectory 'out.iso'
    if (Test-Path -LiteralPath $legacy) {
        return (Resolve-Path -LiteralPath $legacy).Path
    }
    return $null
}

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
if (-not [string]::IsNullOrWhiteSpace($RequireLane) -and $lane -ne $RequireLane) {
    throw "lane must be $RequireLane for this assert, got '$lane' (do not flash a Test workdir as Primary)"
}

if ($RequireLane -eq 'Release') {
    $packageStrict = $false
    if ($evidence.PSObject.Properties.Name -contains 'packageStrict') {
        $packageStrict = [bool]$evidence.packageStrict
    }
    if (-not $packageStrict) {
        throw 'packageStrict must be true for Release Gate B assert (soft Release evidence is not wipe media)'
    }
}

$digestMap = @{}
if ($evidence.PSObject.Properties.Name -contains 'digests' -and $null -ne $evidence.digests) {
    foreach ($p in $evidence.digests.PSObject.Properties) {
        $digestMap[[string]$p.Name] = [string]$p.Value
    }
}

if ($RequireOutputIso) {
    $outIso = Resolve-WinMintOutputIso -WorkDirectory $WorkDirectory -Evidence $evidence
    if ([string]::IsNullOrWhiteSpace($outIso) -or -not (Test-Path -LiteralPath $outIso)) {
        throw "Output ISO missing under $WorkDirectory (expected evidence.outputIsoPath, winmint_*.iso, or legacy out.iso)"
    }
    if (-not $digestMap.ContainsKey('outputIso.sha256') -or [string]::IsNullOrWhiteSpace($digestMap['outputIso.sha256'])) {
        throw 'outputIso.sha256 digest missing/empty in evidence.json'
    }
    $liveIsoSha = (Get-FileHash -LiteralPath $outIso -Algorithm SHA256).Hash.ToLowerInvariant()
    $claimedIsoSha = $digestMap['outputIso.sha256'].ToLowerInvariant()
    if ($liveIsoSha -ne $claimedIsoSha) {
        throw "outputIso.sha256 mismatch: evidence=$claimedIsoSha live=$liveIsoSha (re-run BuildIso or refresh evidence)"
    }
}

# Single-image apply: LaunchApply must target index 1 (not source Pro index 3).
$bootMarker = Join-Path $WorkDirectory 'media\sources\.winmint-boot-apply'
$bootWim = Join-Path $WorkDirectory 'media\sources\boot.wim'
if (Test-Path -LiteralPath $bootWim) {
    if (-not (Test-Path -LiteralPath $bootMarker)) {
        throw "WinPE apply marker missing: $bootMarker"
    }
    $markerText = (Get-Content -LiteralPath $bootMarker -Raw -Encoding utf8).Trim()
    if ($markerText -ne 'apply+wimIndex=1') {
        throw "WinPE apply marker must be apply+wimIndex=1 (got '$markerText')"
    }

    # Marker alone is not enough — verify LaunchApply.cmd inside boot.wim index 1.
    $bootMount = Join-Path $WorkDirectory '_metal-boot-assert'
    if (Test-Path -LiteralPath $bootMount) {
        & dism.exe /English /Unmount-Image /MountDir:$bootMount /Discard 2>$null | Out-Null
        Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Force -Path $bootMount | Out-Null
    try {
        & dism.exe /English /Mount-Image /ImageFile:$bootWim /Index:1 /MountDir:$bootMount /ReadOnly
        if ($LASTEXITCODE -ne 0) { throw "Mount boot.wim:1 for metal assert failed: $LASTEXITCODE" }
        $launchPath = Join-Path $bootMount 'Windows\System32\LaunchApply.cmd'
        if (-not (Test-Path -LiteralPath $launchPath)) {
            throw 'LaunchApply.cmd missing inside boot.wim index 1'
        }
        $launchBody = Get-Content -LiteralPath $launchPath -Raw -Encoding utf8
        if ($launchBody -notmatch '/Index:1\b') {
            throw 'LaunchApply.cmd must Apply-Image /Index:1 (single-image export)'
        }
        if ($launchBody -match '/Index:(\d+)' -and [int]$Matches[1] -ne 1) {
            throw "LaunchApply.cmd has wrong /Index:$($Matches[1]) (need 1)"
        }
        $winpeshlPath = Join-Path $bootMount 'Windows\System32\winpeshl.ini'
        if (-not (Test-Path -LiteralPath $winpeshlPath)) {
            throw 'winpeshl.ini missing inside boot.wim index 1'
        }
        $winpeshlBody = Get-Content -LiteralPath $winpeshlPath -Raw -Encoding utf8
        if ($winpeshlBody -notmatch 'LaunchApply\.cmd') {
            throw 'winpeshl.ini must launch LaunchApply.cmd'
        }
    }
    finally {
        & dism.exe /English /Unmount-Image /MountDir:$bootMount /Discard 2>$null | Out-Null
        Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
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

$expectFu = $ExpectFuPosture -or ($RequireLane -eq 'Release')
if ($expectFu) {
    $fuDigests = [ordered]@{
        'policy.cloudContent.DisableWindowsConsumerFeatures' = '1'
        'policy.cloudContent.DisableSoftLanding'              = '1'
        'policy.store.AutoDownload'                          = '2'
    }
    foreach ($key in $fuDigests.Keys) {
        if (-not $digestMap.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($digestMap[$key])) {
            throw "FU posture digest missing in evidence.json: $key"
        }
        if ($digestMap[$key] -ne $fuDigests[$key]) {
            throw "FU posture digest $key expected $($fuDigests[$key]), got '$($digestMap[$key])'"
        }
    }

    $jobsPath = Join-Path $WorkDirectory 'payload\jobs.json'
    if (-not (Test-Path -LiteralPath $jobsPath)) {
        throw "payload/jobs.json missing: $jobsPath (ExpectFuPosture / Release)"
    }
    $jobsDoc = Get-Content -LiteralPath $jobsPath -Raw -Encoding utf8 | ConvertFrom-Json
    $kinds = @($jobsDoc.jobs | ForEach-Object { [string]$_.kind })
    foreach ($need in @('scoop.batch', 'shell.stamp')) {
        if ($kinds -notcontains $need) {
            throw "payload/jobs.json must include $need for Release FU/shell posture"
        }
    }

    $importPath = Join-Path $WorkDirectory 'payload\winget-import.json'
    if (-not (Test-Path -LiteralPath $importPath)) {
        throw "payload/winget-import.json missing: $importPath (ExpectFuPosture / Release)"
    }
    $importDoc = Get-Content -LiteralPath $importPath -Raw -Encoding utf8 | ConvertFrom-Json
    $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($src in @($importDoc.Sources)) {
        foreach ($pkg in @($src.Packages)) {
            $pkgId = [string]$pkg.PackageIdentifier
            if (-not [string]::IsNullOrWhiteSpace($pkgId)) { [void]$ids.Add($pkgId) }
        }
    }
    foreach ($needId in @(
            'Git.MinGit',
            'Microsoft.PowerShell',
            'Microsoft.WindowsTerminal',
            'Microsoft.Coreutils',
            'Nilesoft.Shell'
        )) {
        if (-not $ids.Contains($needId)) {
            throw "winget-import.json missing shell-core id '$needId' (Release)"
        }
    }
}

$acceptance = [ordered]@{
    schemaVersion = 'winmint.metal.acceptance/v1'
    lane          = $lane
    preWipeOnly   = $true
}
if ($expectFu) {
    $acceptance.fuPosture = $true
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
