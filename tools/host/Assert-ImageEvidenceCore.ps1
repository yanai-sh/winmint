#requires -Version 7.6
Set-StrictMode -Version Latest

<#
.SYNOPSIS
  Shared ImageEvidence schema/lane/digest/expected-evidence asserts for S4 and S5.
  Gate B polarity matches HostReview.IsGateB (Release ∧ packageStrict).
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
