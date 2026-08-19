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

$threw = $false
try {
    Resolve-WinMintQualityUpdate -Version '10.0.26100.1' -Architecture 'ARM64' -ImageUbr 1 `
        -SearchHtml $search25 -DetailsHtml $details | Out-Null
}
catch { $threw = $true }
if (-not $threw) { throw 'Test-QualityCatalog: expected 24H2 not to pick 25H2 rows' }

$urls = ConvertFrom-WinMintCatalogDownloadDialog -Text (Get-Content -LiteralPath (Join-Path $fx 'download-dialog-kb5121003.txt') -Raw)
$msu = Select-WinMintCatalogMsuUrl -Urls $urls
if ($msu -notmatch 'kb5121003-arm64') { throw "Test-QualityCatalog: msu $msu" }
if (-not (Test-WinMintDownloadWindowsupdateUri -Uri $msu)) { throw 'Test-QualityCatalog: download host' }
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

Write-Output 'Test-QualityCatalog ok'
exit 0
