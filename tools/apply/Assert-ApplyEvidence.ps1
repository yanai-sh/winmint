#requires -Version 7.6
<#
.SYNOPSIS
  Assert ImageServicing Apply workdir evidence (S5 Host Apply). Pure — no Apply, no Hyper-V, no install.

.DESCRIPTION
  Pre-wipe gate: validates offline build output on the physical build host before any USB/destructive install.

  Expects under -WorkDirectory:
    evidence.json              (winmint.image.evidence/v1)
    logs/WinMint-DriverInventory.json   (when -ExpectDrivers)
    out.iso / winmint_*.iso   (optional when -RequireOutputIso; prefer evidence.outputIsoPath)

  Writes apply-acceptance.json on success.
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

. (Join-Path $PSScriptRoot '..\Resolve-OutputIso.ps1')
. (Join-Path $PSScriptRoot '..\host\Assert-ImageEvidenceCore.ps1')
# Same definition of "patched" the patcher uses — the gate must not certify media it would re-patch.
. (Join-Path $PSScriptRoot '..\..\servicing\WinPeApplyContract.ps1')

if (-not (Test-Path -LiteralPath $WorkDirectory)) {
    throw "Work directory missing: $WorkDirectory"
}

$core = Assert-WinMintImageEvidence `
    -EvidencePath (Join-Path $WorkDirectory 'evidence.json') `
    -ExpectedEvidencePath (Join-Path $WorkDirectory 'expected-evidence.json') `
    -RequireLane $RequireLane `
    -EvidenceLabel 'evidence.json'
$evidence = $core.Evidence
$lane = $core.Lane
$digestMap = $core.DigestMap
$expected = $core.Expected

if ($null -ne $expected) {
    if ([bool]$expected.expectDrivers) { $ExpectDrivers = $true }
    if ([bool]$expected.expectFuPosture) { $ExpectFuPosture = $true }
    $jobsPath = Join-Path $WorkDirectory 'payload\jobs.json'
    foreach ($need in @($expected.requiredJobKinds)) {
        if (-not (Test-Path -LiteralPath $jobsPath)) {
            throw "payload/jobs.json missing: $jobsPath ($need)"
        }
        $jobsDoc = Get-Content -LiteralPath $jobsPath -Raw -Encoding utf8 | ConvertFrom-Json
        $kinds = @($jobsDoc.jobs | ForEach-Object { [string]$_.kind })
        if ($kinds -notcontains [string]$need) {
            throw "payload/jobs.json must include $need"
        }
    }
    if (@($expected.requiredWingetIds).Count -gt 0) {
        $importPath = Join-Path $WorkDirectory 'payload\winget-import.json'
        if (-not (Test-Path -LiteralPath $importPath)) {
            throw "winget-import.json missing: $importPath"
        }
        $importDoc = Get-Content -LiteralPath $importPath -Raw -Encoding utf8 | ConvertFrom-Json
        $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($src in @($importDoc.Sources)) {
            foreach ($pkg in @($src.Packages)) {
                $pkgId = [string]$pkg.PackageIdentifier
                if (-not [string]::IsNullOrWhiteSpace($pkgId)) { [void]$ids.Add($pkgId) }
            }
        }
        foreach ($needId in @($expected.requiredWingetIds)) {
            if (-not $ids.Contains([string]$needId)) {
                throw "winget-import.json missing shell-core id '$needId'"
            }
        }
    }
    $wslIds = @($expected.requiredWslPackageIds)
    $jobsPath = Join-Path $WorkDirectory 'payload\jobs.json'
    $wslJobs = @()
    if (Test-Path -LiteralPath $jobsPath) {
        $jobsDoc = Get-Content -LiteralPath $jobsPath -Raw -Encoding utf8 | ConvertFrom-Json
        $wslJobs = @($jobsDoc.jobs | Where-Object { [string]$_.kind -eq 'wsl' })
    }
    if ($wslJobs.Count -gt 0 -and $wslIds.Count -eq 0) {
        throw 'expected-evidence.json requiredWslPackageIds missing or empty but payload/jobs.json has wsl jobs'
    }
    if ($wslIds.Count -gt 0) {
        $catalogPath = Join-Path $PSScriptRoot '..\..\config\packages.json'
        if (-not (Test-Path -LiteralPath $catalogPath)) {
            throw "package catalog missing for WSL assert: $catalogPath"
        }
        $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding utf8 | ConvertFrom-Json
        $catalogWslInstallIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($null -ne $catalog.wslDistros) {
            foreach ($p in $catalog.wslDistros.PSObject.Properties) {
                $row = $p.Value
                $installId = [string]$row.installId
                if ([string]::IsNullOrWhiteSpace($installId)) { $installId = [string]$p.Name }
                if (-not [string]::IsNullOrWhiteSpace($installId)) {
                    [void]$catalogWslInstallIds.Add($installId)
                }
            }
        }
        foreach ($needId in $wslIds) {
            if (-not $catalogWslInstallIds.Contains([string]$needId)) {
                throw "requiredWslPackageId '$needId' is not a catalog installId"
            }
        }
        if (-not (Test-Path -LiteralPath $jobsPath)) {
            throw "payload/jobs.json missing: $jobsPath (requiredWslPackageIds)"
        }
        if ($wslJobs.Count -eq 0) {
            $jobsDoc = Get-Content -LiteralPath $jobsPath -Raw -Encoding utf8 | ConvertFrom-Json
            $wslJobs = @($jobsDoc.jobs | Where-Object { [string]$_.kind -eq 'wsl' })
        }
        $jobPackageIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($job in $wslJobs) {
            $pkgId = [string]$job.packageId
            if (-not [string]::IsNullOrWhiteSpace($pkgId)) { [void]$jobPackageIds.Add($pkgId) }
        }
        foreach ($needId in $wslIds) {
            if (-not $jobPackageIds.Contains([string]$needId)) {
                throw "payload/jobs.json missing wsl job packageId '$needId'"
            }
        }
        $expectedWsl = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($needId in $wslIds) { [void]$expectedWsl.Add([string]$needId) }
        foreach ($job in $wslJobs) {
            $pkgId = [string]$job.packageId
            if ([string]::IsNullOrWhiteSpace($pkgId)) {
                throw 'payload/jobs.json wsl job missing packageId'
            }
            if (-not $expectedWsl.Contains($pkgId)) {
                throw "payload/jobs.json wsl packageId '$pkgId' not listed in expected-evidence requiredWslPackageIds"
            }
        }
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
    $expectedMarker = Get-WinPeApplyMarkerText
    $markerText = (Get-Content -LiteralPath $bootMarker -Raw -Encoding utf8).Trim()
    if ($markerText -ne $expectedMarker) {
        throw "WinPE apply marker must be $expectedMarker (got '$markerText')"
    }

    # Marker alone is not enough — verify LaunchApply.cmd inside every boot.wim index.
    $info = & dism.exe /English /Get-WimInfo /WimFile:$bootWim 2>&1 | Out-String
    $indexes = @([regex]::Matches($info, '(?m)^Index : (\d+)\s*$') | ForEach-Object { [int]$_.Groups[1].Value })
    if ($indexes.Count -eq 0) { throw 'boot.wim has no indexes' }

    $bootMount = Join-Path $WorkDirectory '_apply-boot-assert'
    if (Test-Path -LiteralPath $bootMount) {
        & dism.exe /English /Unmount-Image /MountDir:$bootMount /Discard 2>$null | Out-Null
        Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
    }
    foreach ($index in $indexes) {
        New-Item -ItemType Directory -Force -Path $bootMount | Out-Null
        $primaryError = $null
        try {
            & dism.exe /English /Mount-Image /ImageFile:$bootWim /Index:$index /MountDir:$bootMount /ReadOnly
            if ($LASTEXITCODE -ne 0) { throw "Mount boot.wim:$index for apply assert failed: $LASTEXITCODE" }
            $defects = Get-WinPeApplyDefect -MountDir $bootMount -WorkDirectory $WorkDirectory
            if ($defects.Count -gt 0) {
                throw "boot.wim index $index is not apply media: $($defects -join '; ')"
            }
        }
        catch {
            $primaryError = $_
            throw
        }
        finally {
            & dism.exe /English /Unmount-Image /MountDir:$bootMount /Discard 2>$null | Out-Null
            $unmountExit = $LASTEXITCODE
            Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
            if ($unmountExit -ne 0) {
                $message = "Unmount boot.wim:$index after apply assert failed: $unmountExit"
                if ($null -eq $primaryError) { throw $message }
                Write-Warning "$message (preserving earlier error: $($primaryError.Exception.Message))"
            }
        }
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
    foreach ($src in @($importDoc.Sources)) {
        $id = [string]$src.SourceDetails.Identifier
        if ($id -ne 'Microsoft.Winget.Source_8wekyb3d8bbwe') {
            throw "winget-import.json Identifier must be Microsoft.Winget.Source_8wekyb3d8bbwe (winget source export), got '$id'"
        }
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
    schemaVersion = 'winmint.apply.acceptance/v1'
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

$acceptancePath = Join-Path $WorkDirectory 'apply-acceptance.json'
$acceptance | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $acceptancePath -Encoding utf8
Write-Output "Host Apply acceptance OK (lane=$lane pre-wipe-only)"
exit 0
