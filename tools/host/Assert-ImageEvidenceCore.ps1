#requires -Version 7.6
Set-StrictMode -Version Latest

<#
.SYNOPSIS
  Shared ImageEvidence schema/lane/digest/expected-evidence asserts for S4 and S5.

.NOTES
  Two Gate B predicates — do not equate them:

  Test-WinMintIsGateB / Assert-WinMintGateB
    Apply evidence gate: lane ∧ packageStrict (Release wipe-path gating for soft Release).

  Test-WinMintIsWipeReadyGateB / Assert-WinMintWipeReadyGateB
    Wipe-ready claim mirroring HostReview.IsGateB: Release ∧ packageStrict ∧ packageWireHonest.
    packageWireHonest is a frozen expected-evidence fact (materialize) — PS must not re-plan it.
#>

function Test-WinMintIsGateB {
    param(
        [Parameter(Mandatory)]
        [string] $Lane,

        [Parameter(Mandatory)]
        [bool] $PackageStrict
    )
    return $Lane -eq 'Release' -and $PackageStrict
}

function Assert-WinMintGateB {
    param(
        [Parameter(Mandatory)]
        [string] $Lane,

        [Parameter(Mandatory)]
        [bool] $PackageStrict,

        [string] $Context = 'Gate B'
    )
    if (-not (Test-WinMintIsGateB -Lane $Lane -PackageStrict:$PackageStrict)) {
        throw ("$Context requires Release and packageStrict " +
            "(soft Release evidence is not wipe media; lane='$Lane' packageStrict=$PackageStrict)")
    }
}

function Test-WinMintIsWipeReadyGateB {
    param(
        [Parameter(Mandatory)]
        [string] $Lane,

        [Parameter(Mandatory)]
        [bool] $PackageStrict,

        [Parameter(Mandatory)]
        [bool] $PackageWireHonest
    )
    return (Test-WinMintIsGateB -Lane $Lane -PackageStrict:$PackageStrict) -and $PackageWireHonest
}

function Assert-WinMintWipeReadyGateB {
    param(
        [Parameter(Mandatory)]
        [string] $Lane,

        [Parameter(Mandatory)]
        [bool] $PackageStrict,

        [Parameter(Mandatory)]
        [bool] $PackageWireHonest,

        [string] $Context = 'wipe-ready Gate B'
    )
    if (-not (Test-WinMintIsWipeReadyGateB -Lane $Lane -PackageStrict:$PackageStrict -PackageWireHonest:$PackageWireHonest)) {
        throw ("$Context requires Release, packageStrict, and packageWireHonest " +
            "(HostReview.IsGateB; lane='$Lane' packageStrict=$PackageStrict packageWireHonest=$PackageWireHonest)")
    }
}

function Get-WinMintExpectedPackageWireHonest {
    param(
        [Parameter(Mandatory)]
        $Expected
    )
    # Fail-closed: missing fact is not wipe-ready honesty.
    if ($null -eq $Expected) { return $false }
    if ($Expected.PSObject.Properties.Name -notcontains 'packageWireHonest') { return $false }
    return [bool]$Expected.packageWireHonest
}

function Assert-WinMintImageEvidence {
    param(
        [Parameter(Mandatory)]
        [string] $EvidencePath,

        [string] $ExpectedEvidencePath = '',

        [ValidateSet('', 'Test', 'Release')]
        [string] $RequireLane = '',

        # Error text fragment: "evidence.json" vs "apply/evidence.json"
        [string] $EvidenceLabel = 'evidence.json'
    )

    if (-not (Test-Path -LiteralPath $EvidencePath -PathType Leaf)) {
        throw "Apply $EvidenceLabel missing: $EvidencePath"
    }

    $evidence = Get-Content -LiteralPath $EvidencePath -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string]$evidence.schemaVersion -ne 'winmint.image.evidence/v1') {
        throw "unexpected evidence schema '$($evidence.schemaVersion)'"
    }

    $lane = $null
    if ($evidence.PSObject.Properties.Name -contains 'lane' -and $evidence.lane) {
        $lane = [string]$evidence.lane
    }
    if (-not $lane) {
        throw "lane marker missing ($EvidenceLabel must include lane)"
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
        # Apply evidence gate only — wipe-ready needs expected-evidence.packageWireHonest below.
        Assert-WinMintGateB -Lane $lane -PackageStrict:$packageStrict -Context 'Release Gate B assert'
    }

    $digestMap = @{}
    if ($evidence.PSObject.Properties.Name -contains 'digests' -and $null -ne $evidence.digests) {
        foreach ($p in $evidence.digests.PSObject.Properties) {
            $digestMap[[string]$p.Name] = [string]$p.Value
        }
    }

    $expected = $null
    if (-not [string]::IsNullOrWhiteSpace($ExpectedEvidencePath) -and
        (Test-Path -LiteralPath $ExpectedEvidencePath -PathType Leaf)) {
        $expected = Get-Content -LiteralPath $ExpectedEvidencePath -Raw -Encoding utf8 | ConvertFrom-Json
        if ([string]$expected.schemaVersion -ne 'winmint.expected-evidence/v1') {
            throw "unexpected expected-evidence schema '$($expected.schemaVersion)'"
        }
        if ([string]::IsNullOrWhiteSpace($RequireLane) -and [string]$expected.lane -ne $lane) {
            throw "lane must be $($expected.lane) for this assert, got '$lane'"
        }
        if ([bool]$expected.packageStrict) {
            $packageStrict = $false
            if ($evidence.PSObject.Properties.Name -contains 'packageStrict') {
                $packageStrict = [bool]$evidence.packageStrict
            }
            Assert-WinMintGateB -Lane $lane -PackageStrict:$packageStrict -Context 'expected-evidence Gate B'
            $wireHonest = Get-WinMintExpectedPackageWireHonest -Expected $expected
            Assert-WinMintWipeReadyGateB `
                -Lane $lane `
                -PackageStrict:$packageStrict `
                -PackageWireHonest:$wireHonest `
                -Context 'expected-evidence wipe-ready Gate B'
        }
        elseif ($RequireLane -eq 'Release') {
            # Primary / RequireLane Release: wipe-ready claim consumes frozen packageWireHonest.
            $packageStrict = $false
            if ($evidence.PSObject.Properties.Name -contains 'packageStrict') {
                $packageStrict = [bool]$evidence.packageStrict
            }
            $wireHonest = Get-WinMintExpectedPackageWireHonest -Expected $expected
            Assert-WinMintWipeReadyGateB `
                -Lane $lane `
                -PackageStrict:$packageStrict `
                -PackageWireHonest:$wireHonest `
                -Context 'RequireLane Release wipe-ready Gate B'
        }
        foreach ($key in @($expected.requiredDigestKeys)) {
            if (-not $digestMap.ContainsKey([string]$key) -or [string]::IsNullOrWhiteSpace($digestMap[[string]$key])) {
                throw "expected digest missing in ${EvidenceLabel}: $key"
            }
        }
        if ($expected.PSObject.Properties.Name -contains 'requiredDigestValues' -and $null -ne $expected.requiredDigestValues) {
            foreach ($p in $expected.requiredDigestValues.PSObject.Properties) {
                $got = [string]$digestMap[$p.Name]
                if ($got -ne [string]$p.Value) {
                    throw "expected digest $($p.Name) wanted $($p.Value), got '$got'"
                }
            }
        }
    }

    return [pscustomobject]@{
        Evidence  = $evidence
        Lane      = $lane
        DigestMap = $digestMap
        Expected  = $expected
    }
}

function Assert-WinMintDmaSettleBundle {
    param(
        [Parameter(Mandatory)]
        [string] $BundlePath
    )

    if (-not (Test-Path -LiteralPath $BundlePath -PathType Leaf)) {
        return
    }

    $bundle = Get-Content -LiteralPath $BundlePath -Raw -Encoding utf8 | ConvertFrom-Json
    $dmaEnabled = $false
    if ($bundle.PSObject.Properties.Name -contains 'dmaEnabled') {
        $dmaEnabled = [bool]$bundle.dmaEnabled
    }
    if (-not $dmaEnabled) {
        return
    }

    $settle = $null
    if ($bundle.PSObject.Properties.Name -contains 'settle') {
        $settle = $bundle.settle
    }
    $locale = ''
    $timeZoneId = ''
    $geoId = $null
    $locationServicesEnabled = $null
    if ($null -ne $settle) {
        if ($settle.PSObject.Properties.Name -contains 'locale') {
            $locale = [string]$settle.locale
        }
        if ($settle.PSObject.Properties.Name -contains 'timeZoneId') {
            $timeZoneId = [string]$settle.timeZoneId
        }
        if ($settle.PSObject.Properties.Name -contains 'geoId') {
            $geoId = $settle.geoId
        }
        if ($settle.PSObject.Properties.Name -contains 'locationServicesEnabled') {
            $locationServicesEnabled = $settle.locationServicesEnabled
        }
    }

    $incomplete = [string]::IsNullOrWhiteSpace($locale) `
        -or [string]::IsNullOrWhiteSpace($timeZoneId) `
        -or $null -eq $geoId `
        -or $null -eq $locationServicesEnabled
    if ($incomplete) {
        throw ('payload/bundle.json dma.settle requires locale, geoId, timeZoneId, and locationServicesEnabled ' +
            'when dmaEnabled.')
    }
}
