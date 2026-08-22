#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'servicing\Resolve-WinMintQualityUpdate.ps1')
$fx = Join-Path $repo 'tests\fixtures\catalog'
$search25 = Get-Content -LiteralPath (Join-Path $fx 'search-25h2-mixed.html') -Raw
$searchJunk = Get-Content -LiteralPath (Join-Path $fx 'search-26h1-and-x64.html') -Raw
$details = Get-Content -LiteralPath (Join-Path $fx 'details-kb5121003.html') -Raw

$apply = Resolve-WinMintQualityUpdate -Version '10.0.26200.1' -Architecture 'ARM64' -ImageUbr 8037 `
    -SearchHtml $search25 -DetailsHtml $details
if ($apply.Skipped -or $apply.Kb -ne 'KB5121003' -or $apply.PackageUbr -ne 9168 -or $apply.Label -ne '25H2') {
    throw "Test-QualityCatalog: apply $($apply.Kb) skip=$($apply.Skipped) ubr=$($apply.PackageUbr)"
}
if ($apply.Title -match '26H1|x64-based|Preview') {
    throw "Test-QualityCatalog: picked junk $($apply.Title)"
}

$skip = Resolve-WinMintQualityUpdate -Version '10.0.26200.1' -Architecture 'ARM64' -ImageUbr 9168 `
    -SearchHtml $search25 -DetailsHtml $details
if (-not $skip.Skipped -or $skip.Kb -ne 'KB5121003') {
    throw "Test-QualityCatalog: expected skip at image UBR 9168"
}

$threw = $false
try {
    Resolve-WinMintQualityUpdate -Version '10.0.28000.1' -Architecture 'ARM64' -ImageUbr 1 `
        -SearchHtml $search25 -DetailsHtml $details | Out-Null
}
catch { $threw = $true }
if (-not $threw) { throw 'Test-QualityCatalog: expected refuse 26H1 family' }

$threw = $false
try {
    Resolve-WinMintQualityUpdate -Version '10.0.26200.1' -Architecture 'x64' -ImageUbr 1 `
        -SearchHtml $search25 -DetailsHtml $details | Out-Null
}
catch { $threw = $true }
if (-not $threw) { throw 'Test-QualityCatalog: expected refuse x64' }

$threw = $false
try {
    Resolve-WinMintQualityUpdate -Version '10.0.26200.1' -Architecture 'ARM64' -ImageUbr 1 `
        -SearchHtml $searchJunk -DetailsHtml $details | Out-Null
}
catch { $threw = $true }
if (-not $threw) { throw 'Test-QualityCatalog: expected refuse 26H1/x64-only fixture' }

# 24H2 (26100) is out of product scope — WinMint supports 25H2+ only.
$threw = $false
try {
    Resolve-WinMintQualityUpdate -Version '10.0.26100.1' -Architecture 'ARM64' -ImageUbr 1 `
        -SearchHtml $search25 -DetailsHtml $details | Out-Null
}
catch {
    $threw = $true
    if ($_.Exception.Message -notmatch 'No Catalog LCU mapping') {
        throw "Test-QualityCatalog: family 26100 must fail closed on mapping, got: $($_.Exception.Message)"
    }
}
if (-not $threw) { throw 'Test-QualityCatalog: expected family 26100 to fail closed (25H2+ only)' }

# 25H2 enablement: RollupFix package identity stays on 26100.<ubr> even when WIM family is 26200.
$rollup25 = @"
Package Identity : Package_for_RollupFix~31bf3856ad364e35~arm64~~26100.9168.1.19
State : Installed
"@
try {
    Test-WinMintRollupFixPresent -GetPackagesText $rollup25 -Family 26200 -Ubr 9168 -Architecture 'ARM64'
}
catch {
    throw "Test-QualityCatalog: 25H2 must accept RollupFix 26100.<ubr>: $($_.Exception.Message)"
}
$threw = $false
try {
    Test-WinMintRollupFixPresent -GetPackagesText $rollup25 -Family 26200 -Ubr 9168 -Architecture 'x64'
}
catch { $threw = $true }
if (-not $threw) { throw 'Test-QualityCatalog: RollupFix assert must still require matching arch' }
$threw = $false
try {
    Test-WinMintRollupFixPresent -GetPackagesText $rollup25 -Family 26200 -Ubr 9999 -Architecture 'ARM64'
}
catch { $threw = $true }
if (-not $threw) { throw 'Test-QualityCatalog: RollupFix assert must still require matching UBR' }

# Rowless Catalog page (markup change / throttle / outage) must fail closed with the
# Catalog message, not a null -Rows parameter binding error (22 Aug prove-out failure).
$threw = $false
try {
    Resolve-WinMintQualityUpdate -Version '10.0.26200.1' -Architecture 'ARM64' -ImageUbr 1 `
        -SearchHtml '<html><body>We did not find any results for your search.</body></html>' `
        -DetailsHtml $details | Out-Null
}
catch {
    $threw = $true
    if ($_.Exception.Message -notmatch 'Catalog had no ARM64.*parsed 0 Catalog search rows') {
        throw "Test-QualityCatalog: rowless search must throw the Catalog fail-closed message, got: $($_.Exception.Message)"
    }
}
if (-not $threw) { throw 'Test-QualityCatalog: expected rowless search to throw' }

# Transient rowless Catalog page: search retries and recovers without caller involvement.
# Rowless attempts dump the raw HTML for forensics and warn into the stage log.
$dumpDir = Join-Path ([IO.Path]::GetTempPath()) ('winmint-quality-rowless-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $dumpDir | Out-Null
try {
    $script:fetchCalls = 0
    $goodHtml = $search25
    $retried = Invoke-WinMintCatalogSearchHtml -Query 'q' -RetryDelaysSeconds @(0, 0, 0, 0) `
        -RowlessDumpDir $dumpDir -WarningAction SilentlyContinue -WarningVariable retryWarnings -Fetch {
        param($Uri)
        $script:fetchCalls++
        if ($script:fetchCalls -lt 2) { return '<html>rowless chrome page</html>' }
        return $goodHtml
    }
    if ($script:fetchCalls -ne 2) { throw "Test-QualityCatalog: expected retry after rowless page (fetches=$script:fetchCalls)" }
    $retriedRows = ConvertFrom-WinMintCatalogSearchHtml -Html $retried
    if (@($retriedRows).Count -lt 1) {
        throw 'Test-QualityCatalog: retry must return the page that parsed rows'
    }
    if (@($retryWarnings).Count -ne 1 -or $retryWarnings[0] -notmatch 'rowless \(attempt 1 of 5.*saved .*winmint-catalog-rowless-') {
        throw "Test-QualityCatalog: rowless retry must warn with attempt count and dump path, got: $retryWarnings"
    }
    $script:fetchCalls = 0
    $exhausted = Invoke-WinMintCatalogSearchHtml -Query 'q' -RetryDelaysSeconds @(0, 0, 0, 0) `
        -RowlessDumpDir $dumpDir -WarningAction SilentlyContinue -Fetch {
        param($Uri)
        $script:fetchCalls++
        return '<html>rowless chrome page</html>'
    }
    if ($script:fetchCalls -ne 5) { throw "Test-QualityCatalog: expected 5 attempts before giving up (fetches=$script:fetchCalls)" }
    $exhaustedRows = ConvertFrom-WinMintCatalogSearchHtml -Html $exhausted
    if (@($exhaustedRows).Count -ne 0) {
        throw 'Test-QualityCatalog: exhausted retries must surface the rowless page for fail-closed callers'
    }
    $dumps = @(Get-ChildItem -LiteralPath $dumpDir -Filter 'winmint-catalog-rowless-*.html' -File)
    if ($dumps.Count -ne 6) {
        throw "Test-QualityCatalog: expected 6 rowless forensics dumps (1 recovered + 5 exhausted), got $($dumps.Count)"
    }

    # A thrown fetch (connection reset mid-spell) rides the same backoff ladder.
    $script:fetchCalls = 0
    $errRecovered = Invoke-WinMintCatalogSearchHtml -Query 'q' -RetryDelaysSeconds @(0, 0) `
        -RowlessDumpDir $dumpDir -WarningAction SilentlyContinue -Fetch {
        param($Uri)
        $script:fetchCalls++
        if ($script:fetchCalls -lt 2) { throw 'Catalog search failed (host offline or Catalog down): reset' }
        return $goodHtml
    }
    if ($script:fetchCalls -ne 2) { throw "Test-QualityCatalog: expected retry after thrown fetch (fetches=$script:fetchCalls)" }
    if (@(ConvertFrom-WinMintCatalogSearchHtml -Html $errRecovered).Count -lt 1) {
        throw 'Test-QualityCatalog: thrown-fetch retry must return the page that parsed rows'
    }
    $script:fetchCalls = 0
    $threw = $false
    try {
        Invoke-WinMintCatalogSearchHtml -Query 'q' -RetryDelaysSeconds @(0, 0) `
            -RowlessDumpDir $dumpDir -WarningAction SilentlyContinue -Fetch {
            param($Uri)
            $script:fetchCalls++
            throw 'Catalog search failed (host offline or Catalog down): reset'
        } | Out-Null
    }
    catch {
        $threw = $true
        if ($_.Exception.Message -notmatch 'Catalog search failed') {
            throw "Test-QualityCatalog: exhausted thrown fetches must rethrow the fetch error, got: $($_.Exception.Message)"
        }
    }
    if (-not $threw) { throw 'Test-QualityCatalog: expected throw after exhausted fetch errors' }
    if ($script:fetchCalls -ne 3) { throw "Test-QualityCatalog: expected 3 fetch attempts before rethrow (fetches=$script:fetchCalls)" }
}
finally {
    Remove-Item -LiteralPath $dumpDir -Recurse -Force -ErrorAction SilentlyContinue
}

$urls = ConvertFrom-WinMintCatalogDownloadDialog -Text (Get-Content -LiteralPath (Join-Path $fx 'download-dialog-kb5121003.txt') -Raw)
$msu = Select-WinMintCatalogMsuUrl -Urls $urls -Kb 'KB5121003'
if ($msu -notmatch 'kb5121003-arm64') { throw "Test-QualityCatalog: msu $msu" }
if (-not (Test-WinMintDownloadWindowsupdateUri -Uri $msu)) { throw 'Test-QualityCatalog: download host' }
$delivery = ConvertFrom-WinMintCatalogDownloadDialog -Text (Get-Content -LiteralPath (Join-Path $fx 'download-dialog-kb5121003-delivery.txt') -Raw)
$deliveryMsu = Select-WinMintCatalogMsuUrl -Urls $delivery -Kb 'KB5121003'
if ($deliveryMsu -notmatch 'kb5121003-arm64') { throw "Test-QualityCatalog: delivery msu $deliveryMsu" }
$ckptFirst = ConvertFrom-WinMintCatalogDownloadDialog -Text (Get-Content -LiteralPath (Join-Path $fx 'download-dialog-checkpoint-first.txt') -Raw)
$ckptPick = Select-WinMintCatalogMsuUrl -Urls $ckptFirst -Kb 'KB5121003'
if ($ckptPick -notmatch 'kb5121003-arm64' -or $ckptPick -match 'kb5043080') {
    throw "Test-QualityCatalog: checkpoint-first picked $ckptPick"
}
$safeOsCab = Select-WinMintCatalogMsuUrl -Urls @(
    'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/x/public/windows11.0-kb5121002-arm64_bd34458fa840a0f0ea95f42346110eaf2e97e1a3.cab'
) -Kb 'KB5121002'
if ($safeOsCab -notmatch 'kb5121002-arm64.*\.cab$') {
    throw "Test-QualityCatalog: Safe OS DU cab leaf $safeOsCab"
}
$threw = $false
try {
    Select-WinMintCatalogMsuUrl -Urls @(
        'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/x/public/windows11.0-kb5043080-arm64_x.msu'
    ) -Kb 'KB5121003' | Out-Null
}
catch { $threw = $true }
if (-not $threw) { throw 'Test-QualityCatalog: expected refuse checkpoint-only dialog for LCU KB' }

$poisonRoot = Join-Path ([IO.Path]::GetTempPath()) ('winmint-quality-poison-' + [guid]::NewGuid().ToString('N'))
$poisonDir = Join-Path $poisonRoot 'KB5121003\arm64\deadbeef'
New-Item -ItemType Directory -Force -Path $poisonDir | Out-Null
Set-Content -LiteralPath (Join-Path $poisonDir 'windows11.0-kb5043080-arm64_x.msu') -Value 'not-an-lcu'
$poisonHit = Resolve-WinMintCachedQualityFile -CacheRoot $poisonRoot -Kb 'KB5121003' -Architecture 'ARM64'
if ($null -ne $poisonHit) { throw "Test-QualityCatalog: poisoned cache must miss, got $poisonHit" }
if (Test-Path -LiteralPath $poisonDir) { throw 'Test-QualityCatalog: poison SHA dir must leave the hit path' }
$quarantined = @(
    Get-ChildItem -LiteralPath (Join-Path $poisonRoot 'quarantine') -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'deadbeef.invalid-*' }
)
if ($quarantined.Count -ne 1) {
    throw "Test-QualityCatalog: expected one quarantined SHA dir, got $($quarantined.Count)"
}
$mixedRoot = Join-Path ([IO.Path]::GetTempPath()) ('winmint-quality-mixed-' + [guid]::NewGuid().ToString('N'))
$goodDir = Join-Path $mixedRoot 'KB5121003\arm64\cafebabe'
$badDir = Join-Path $mixedRoot 'KB5121003\arm64\deadbeef'
New-Item -ItemType Directory -Force -Path $goodDir, $badDir | Out-Null
Set-Content -LiteralPath (Join-Path $goodDir 'windows11.0-kb5121003-arm64_x.msu') -Value 'lcu'
Set-Content -LiteralPath (Join-Path $badDir 'windows11.0-kb5043080-arm64_x.msu') -Value 'ckpt'
$mixedHit = Resolve-WinMintCachedQualityFile -CacheRoot $mixedRoot -Kb 'KB5121003' -Architecture 'ARM64'
if ($mixedHit -notmatch 'kb5121003') { throw "Test-QualityCatalog: mixed cache must hit LCU, got $mixedHit" }
if (Test-Path -LiteralPath $badDir) { throw 'Test-QualityCatalog: mixed poison SHA dir must leave the hit path' }
if (-not (Test-Path -LiteralPath $goodDir)) { throw 'Test-QualityCatalog: mixed LCU SHA dir must stay' }
Remove-Item -LiteralPath $mixedRoot -Recurse -Force
$writeRefuse = Join-Path $poisonRoot 'windows11.0-kb5043080-arm64_x.msu'
Set-Content -LiteralPath $writeRefuse -Value 'not-an-lcu'
$threw = $false
try {
    Save-WinMintQualityCacheFile -CacheRoot $poisonRoot -Kb 'KB5121003' -Architecture 'ARM64' -SourcePath $writeRefuse | Out-Null
}
catch { $threw = $true }
if (-not $threw) { throw 'Test-QualityCatalog: expected refuse writing checkpoint leaf under LCU KB' }
Remove-Item -LiteralPath $poisonRoot -Recurse -Force

if (-not (Test-WinMintDownloadWindowsupdateUri -Uri $deliveryMsu)) { throw 'Test-QualityCatalog: delivery host' }
if (Test-WinMintDownloadWindowsupdateUri -Uri 'https://catalog.update.microsoft.com/DownloadDialog.aspx') {
    throw 'Test-QualityCatalog: Catalog HTML host is not a payload CDN'
}
$threw = $false
try { ConvertFrom-WinMintCatalogDownloadDialog -Text "url:'https://evil.example/payload.msu'" | Out-Null } catch { $threw = $true }
if (-not $threw) { throw 'Test-QualityCatalog: expected refuse non-WU host' }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('winmint-quality-leaf-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $missing = @(Get-WinMintQualityPackageLeaf -PackageDir $tmp -Kind boot)
    if ($missing.Count -ne 0) { throw 'Test-QualityCatalog: missing list must be empty' }
    Write-WinMintQualityPackageLeaf -PackageDir $tmp -Kind boot -Leaf @()
    $empty = @(Get-WinMintQualityPackageLeaf -PackageDir $tmp -Kind boot)
    if ($empty.Count -ne 0) { throw 'Test-QualityCatalog: empty list must skip Add-Package' }
    Write-WinMintQualityPackageLeaf -PackageDir $tmp -Kind boot -Leaf @('SSU.cab', 'LCU.msu', 'SetupDU.cab')
    Write-WinMintQualityPackageLeaf -PackageDir $tmp -Kind winre -Leaf @('SSU.cab', 'SafeOS.cab')
    $boot = @(Get-WinMintQualityPackageLeaf -PackageDir $tmp -Kind boot)
    $winre = @(Get-WinMintQualityPackageLeaf -PackageDir $tmp -Kind winre)
    if (($boot -join ',') -ne 'SSU.cab,LCU.msu,SetupDU.cab') {
        throw "Test-QualityCatalog: boot leaves $($boot -join ',')"
    }
    if (($winre -join ',') -ne 'SSU.cab,SafeOS.cab') {
        throw "Test-QualityCatalog: winre leaves $($winre -join ',')"
    }
    $threw = $false
    try { Write-WinMintQualityPackageLeaf -PackageDir $tmp -Kind boot -Leaf @('..\escape.cab') | Out-Null } catch { $threw = $true }
    if (-not $threw) { throw 'Test-QualityCatalog: expected refuse path leaf' }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$msuProbe = Join-Path ([IO.Path]::GetTempPath()) ('winmint-msu-probe-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $msuProbe | Out-Null
try {
    $wimMsu = Join-Path $msuProbe 'wim.msu'
    $cabMsu = Join-Path $msuProbe 'cab.msu'
    [IO.File]::WriteAllBytes($wimMsu, [Text.Encoding]::ASCII.GetBytes('MSWIM') + [byte[]](0, 0, 0))
    [IO.File]::WriteAllBytes($cabMsu, [Text.Encoding]::ASCII.GetBytes('MSCF') + [byte[]](0, 0, 0))
    if (-not (Test-WinMintQualityMsuIsWim -Path $wimMsu)) { throw 'Test-QualityCatalog: MSWIM must be WIM-MSU' }
    if (Test-WinMintQualityMsuIsWim -Path $cabMsu) { throw 'Test-QualityCatalog: MSCF must not be WIM-MSU' }

    $wimOut = Join-Path $msuProbe 'wim-out'
    $script:appliedWim = $false
    $ssuFromWim = Expand-WinMintQualitySsu -MsuPath $wimMsu -Destination $wimOut -ApplyWim {
        param($Src, $Dst)
        $script:appliedWim = $true
        # DISM-like success-stream noise (empty lines first) must not become the return.
        Write-Output ''
        Write-Output 'Deployment Image Servicing and Management tool'
        Set-Content -LiteralPath (Join-Path $Dst 'SSU-26100.1-arm64.cab') -Value 'ssu' -Encoding ascii
    }
    if (-not $script:appliedWim) { throw 'Test-QualityCatalog: WIM-MSU must use ApplyWim, not expand.exe' }
    if ($ssuFromWim -is [Array]) { throw 'Test-QualityCatalog: Expand must return one path, not DISM stdout array' }
    if ([string]::IsNullOrWhiteSpace($ssuFromWim)) { throw 'Test-QualityCatalog: WIM-MSU SSU path empty' }
    if (-not (Test-Path -LiteralPath $ssuFromWim)) { throw 'Test-QualityCatalog: WIM-MSU SSU path missing' }
    $null = Split-Path -Leaf $ssuFromWim  # must not throw Path empty (regression)

    $cabOut = Join-Path $msuProbe 'cab-out'
    $script:expandedCab = $false
    $ssuFromCab = Expand-WinMintQualitySsu -MsuPath $cabMsu -Destination $cabOut -ExpandCab {
        param($Src, $Dst)
        $script:expandedCab = $true
        Set-Content -LiteralPath (Join-Path $Dst 'SSU-26100.1-arm64.cab') -Value 'ssu' -Encoding ascii
    }
    if (-not $script:expandedCab) { throw 'Test-QualityCatalog: CAB-MSU must use ExpandCab' }
    if (-not (Test-Path -LiteralPath $ssuFromCab)) { throw 'Test-QualityCatalog: CAB-MSU SSU path missing' }
}
finally {
    Remove-Item -LiteralPath $msuProbe -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-QualityCatalog ok'
exit 0
