#requires -Version 7.6
Set-StrictMode -Version Latest
# Maintainer ISO advisory + snapshot (SL7). Dot-source from Invoke-MaintainerCheck.ps1.

# ponytail: fixed gap vs Catalog B-release; raise if retail slipstream expectations change.
$script:WinMintIsoAdvisoryUbrGap = 500

# Matches ImageServicing.DefaultProWimIndex (consumer multi-edition ISOs).
$script:WinMintMaintainerProWimIndex = 3

function Get-WinMintMaintainerHostFixturePath {
    param([Parameter(Mandatory)] [string] $RepoRoot)
    return Join-Path $RepoRoot 'tests\fixtures\maintainer-host.json'
}

function ConvertFrom-WinMintMaintainerHostFixture {
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Maintainer fixture missing: $Path"
    }
    $doc = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($null -eq $doc.sourceIso -or [string]::IsNullOrWhiteSpace([string]$doc.sourceIso.path)) {
        throw 'Maintainer fixture sourceIso.path is required'
    }
    return $doc
}

function Get-WinMintIsoSha256Hex {
    param([Parameter(Mandatory)] [string] $Path)
    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
    return $hash.Hash.ToLowerInvariant()
}

function ConvertFrom-WinMintWimImageUbr {
    param(
        [string] $Version,
        [string] $ServicePackBuild
    )
    $family = 0
    if (-not [string]::IsNullOrWhiteSpace($Version) -and $Version -match '^10\.0\.(\d+)') {
        $family = [int]$Matches[1]
    }
    [int]$sp = 0
    if (-not [string]::IsNullOrWhiteSpace($ServicePackBuild) -and
        [int]::TryParse($ServicePackBuild.Trim(), [ref]$sp)) {
        if ($family -gt 0 -and $sp -ne $family) { return $sp }
    }
    if (-not [string]::IsNullOrWhiteSpace($Version) -and $Version -match '^10\.0\.(\d+)\.(\d+)') {
        $rev = [int]$Matches[2]
        if ($rev -gt 0) { return $rev }
    }
    if ($family -gt 0 -and $sp -eq $family) { return 0 }
    return 0
}

function Test-WinMintSourceIsoWimRow {
    param(
        [Parameter(Mandatory)] $Row,
        [Parameter(Mandatory)] [string] $ExpectedTrain
    )
    $arch = [string]$Row.architecture
    if ($arch -notmatch '(?i)^ARM64$') {
        throw "Source ISO Pro index is not ARM64 (got '$arch')"
    }
    $languages = [string]$Row.languages
    if ($languages.Trim().ToLowerInvariant() -ne 'en-us') {
        throw "Source ISO install language must be en-US (got '$languages')"
    }
    $version = [string]$Row.version
    if ($version -notmatch '^10\.0\.(\d+)') {
        throw "Source ISO Pro Version unrecognized: '$version'"
    }
    $family = [int]$Matches[1]
    if ($ExpectedTrain -eq '25H2' -and $family -ne 26200) {
        throw "Source ISO train mismatch: expected family 26200 (25H2), got $family"
    }
    if ($ExpectedTrain -ne '25H2') {
        throw "Unsupported maintainer train '$ExpectedTrain'"
    }
}

function Get-WinMintMaintainerIsoProbe {
    param(
        [Parameter(Mandatory)] [string] $IsoPath,
        [int] $ProIndex = $script:WinMintMaintainerProWimIndex,
        [scriptblock] $IndexListProvider = {
            param([string] $Path)
            Get-SourceIsoWimIndexList -IsoPath $Path
        }
    )
    $rows = & $IndexListProvider $IsoPath
    $pro = @($rows | Where-Object { [int]$_.index -eq $ProIndex } | Select-Object -First 1)
    if ($pro.Count -lt 1) {
        throw "Source ISO missing WIM index $ProIndex (Windows 11 Pro)"
    }
    return $pro[0]
}

function Test-WinMintMaintainerIsoAdvisory {
    param(
        [Parameter(Mandatory)] [int] $WimUbr,
        [Parameter(Mandatory)] [int] $CatalogUbr,
        [Parameter(Mandatory)] [string] $IsoSha256,
        [string] $SnapshotIsoSha256 = '',
        [int] $UbrGap = $script:WinMintIsoAdvisoryUbrGap
    )
    $messages = [System.Collections.Generic.List[string]]::new()
    $advisory = $false

    $gap = $CatalogUbr - $WimUbr
    if ($gap -ge $UbrGap) {
        if (-not [string]::IsNullOrWhiteSpace($SnapshotIsoSha256) -and
            ($IsoSha256 -eq $SnapshotIsoSha256.Trim().ToLowerInvariant())) {
            $advisory = $true
            $messages.Add(
                "ISO advisory: install.wim UBR $WimUbr is $gap behind Catalog B-release UBR $CatalogUbr " +
                'and the ISO file hash is unchanged since the last maintainer-check. Consider downloading a ' +
                'newer retail 25H2 English (US) ARM64 ISO (English 64-bit) from https://www.microsoft.com/software-download/windows11 ' +
                'and updating tests/fixtures/maintainer-host.json (path, leaf, optional sha256).'
            )
        }
    }
    return [pscustomobject]@{
        Advisory = $advisory
        Gap      = $gap
        Messages = @($messages)
    }
}

function Invoke-WinMintMaintainerIsoCheck {
    param(
        [Parameter(Mandatory)] $Fixture,
        [Parameter(Mandatory)] [int] $CatalogUbr,
        [string] $SnapshotPath = '',
        [scriptblock] $IndexListProvider = {
            param([string] $Path)
            Get-SourceIsoWimIndexList -IsoPath $Path
        }
    )

    $isoPath = [string]$Fixture.sourceIso.path
    if (-not (Test-Path -LiteralPath $isoPath)) {
        throw "Maintainer Source ISO not found: $isoPath"
    }

    $train = [string]$Fixture.sourceIso.train
    if ([string]::IsNullOrWhiteSpace($train)) { $train = '25H2' }

    $isoSha = Get-WinMintIsoSha256Hex -Path $isoPath
    $messages = [System.Collections.Generic.List[string]]::new()
    $fixtureSha = [string]$Fixture.sourceIso.sha256
    if (-not [string]::IsNullOrWhiteSpace($fixtureSha)) {
        $expected = $fixtureSha.Trim().ToLowerInvariant()
        if ($isoSha -ne $expected) {
            $messages.Add(
                'Maintainer ISO SHA-256 does not match sourceIso.sha256 in maintainer-host.json. ' +
                'Update path, leaf, and sha256 after replacing the retail ISO.'
            )
        }
    }

    $row = Get-WinMintMaintainerIsoProbe -IsoPath $isoPath -IndexListProvider $IndexListProvider
    Test-WinMintSourceIsoWimRow -Row $row -ExpectedTrain $train
    $wimUbr = ConvertFrom-WinMintWimImageUbr -Version ([string]$row.version) -ServicePackBuild ([string]$row.build)

    $snapshotSha = ''
    if (-not [string]::IsNullOrWhiteSpace($SnapshotPath) -and (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) {
        try {
            $snap = Get-Content -LiteralPath $SnapshotPath -Raw | ConvertFrom-Json
            $snapshotSha = [string]$snap.isoSha256
        }
        catch {
            Write-Warning "Ignoring unreadable maintainer snapshot: $SnapshotPath"
        }
    }

    $adv = Test-WinMintMaintainerIsoAdvisory `
        -WimUbr $wimUbr `
        -CatalogUbr $CatalogUbr `
        -IsoSha256 $isoSha `
        -SnapshotIsoSha256 $snapshotSha
    foreach ($m in $adv.Messages) { $messages.Add($m) }

    return [pscustomobject]@{
        IsoPath     = $isoPath
        IsoSha256   = $isoSha
        WimUbr      = $wimUbr
        WimVersion  = [string]$row.version
        Advisory    = $adv.Advisory
        FixtureWarn = ($messages.Count -gt 0 -and -not $adv.Advisory)
        Messages    = @($messages)
    }
}

function Write-WinMintMaintainerLastCheck {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] $Payload
    )
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $Payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Invoke-WinMintMaintainerCheckCore {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [string] $ModuleRoot = $RepoRoot,
        [switch] $SkipIso,
        [string] $SnapshotPath = '',
        [scriptblock] $CatalogResolver,
        [scriptblock] $IndexListProvider
    )

    if ([string]::IsNullOrWhiteSpace($SnapshotPath)) {
        $SnapshotPath = Join-Path $RepoRoot '.scratch\maintainer\last-check.json'
    }

    . (Join-Path $ModuleRoot 'servicing\Resolve-WinMintQualityUpdate.ps1')
    . (Join-Path $ModuleRoot 'tools\host\WinMint-QualityCheck.ps1')

    if ($null -eq $CatalogResolver) {
        $CatalogResolver = {
            param([string] $Version, [string] $Architecture, [int] $ImageUbr)
            Invoke-WinMintQualityCatalogResolve -Version $Version -Architecture $Architecture -ImageUbr $ImageUbr
        }
    }

    $qualityFailed = $false
    $qualityError = ''
    $qualityRows = [System.Collections.Generic.List[object]]::new()
    try {
        $resolvedList = @(Invoke-WinMintQualityReconcile -CatalogResolver $CatalogResolver)
        foreach ($r in $resolvedList) { $qualityRows.Add($r) }
    }
    catch {
        $qualityFailed = $true
        $qualityError = $_.Exception.Message
    }

    $isoResult = $null
    $isoAdvisory = $false
    $skipIso = $SkipIso -or ($env:WINMINT_SKIP_ISO -eq '1')
    if (-not $qualityFailed -and -not $skipIso) {
        . (Join-Path $ModuleRoot 'servicing\Get-WimMetadata.ps1')
        $fixturePath = Get-WinMintMaintainerHostFixturePath -RepoRoot $RepoRoot
        $fixture = ConvertFrom-WinMintMaintainerHostFixture -Path $fixturePath
        $catalogUbr = [int]$qualityRows[0].PackageUbr
        $isoParams = @{
            Fixture      = $fixture
            CatalogUbr   = $catalogUbr
            SnapshotPath = $SnapshotPath
        }
        if ($null -ne $IndexListProvider) { $isoParams.IndexListProvider = $IndexListProvider }
        $isoResult = Invoke-WinMintMaintainerIsoCheck @isoParams
        $isoAdvisory = [bool]$isoResult.Advisory
    }

    $payload = [ordered]@{
        schemaVersion = 'winmint.maintainer-last-check/v1'
        recordedUtc   = [DateTimeOffset]::UtcNow.ToString('o')
        quality       = @(
            foreach ($q in $qualityRows) {
                [ordered]@{
                    label      = $q.Label
                    kb         = $q.Kb
                    packageUbr = $q.PackageUbr
                    title      = $q.Title
                }
            }
        )
        iso           = $(if ($null -eq $isoResult) { $null } else {
                [ordered]@{
                    path      = $isoResult.IsoPath
                    sha256    = $isoResult.IsoSha256
                    wimUbr    = $isoResult.WimUbr
                    wimVersion = $isoResult.WimVersion
                    advisory  = $isoResult.Advisory
                }
            })
    }
    Write-WinMintMaintainerLastCheck -Path $SnapshotPath -Payload $payload

    $exitCode = 0
    if ($qualityFailed) { $exitCode = 1 }
    elseif ($isoAdvisory) { $exitCode = 2 }

    return [pscustomobject]@{
        ExitCode      = $exitCode
        QualityFailed = $qualityFailed
        QualityError  = $qualityError
        QualityRows   = @($qualityRows)
        IsoResult     = $isoResult
        IsoAdvisory   = $isoAdvisory
        SnapshotPath  = $SnapshotPath
    }
}
