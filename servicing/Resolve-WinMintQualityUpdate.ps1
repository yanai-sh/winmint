#requires -Version 7.6
Set-StrictMode -Version Latest
# Catalog LCU resolve / BITS / SSU expand / DISM Add-Package. Dot-source helper (ADR-013).
# Live Catalog is Apply + `just quality-check` only — never `just check`.

function Get-WinMintQualityTrain {
    param(
        [Parameter(Mandatory)] [string] $Version,
        [Parameter(Mandatory)] [string] $Architecture
    )
    $arch = $Architecture.Trim()
    if ($arch -notmatch '^(?i)ARM64$') {
        throw "Quality updates require ARM64 (got '$Architecture')"
    }
    if ($Version -notmatch '^10\.0\.(\d+)(?:\.|$)') {
        throw "Unrecognized WIM Version '$Version' (need 10.0.<family>)"
    }
    $family = [int]$Matches[1]
    $label = switch ($family) {
        26200 { '25H2' }
        26100 { '24H2' }
        default { $null }
    }
    if ($null -eq $label) {
        throw "No Catalog LCU mapping for Version family $family (do not guess 26H1)"
    }
    return [pscustomobject]@{
        Family       = $family
        Label        = $label
        Architecture = 'ARM64'
        Query        = "Cumulative Update for Windows 11 Version $label"
    }
}

function ConvertFrom-WinMintCatalogSearchHtml {
    param([Parameter(Mandatory)] [string] $Html)
    $rows = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    $pattern = '(?is)goToDetails\((?:&quot;|&#39;|[''"])([0-9a-fA-F-]{36})(?:&quot;|&#39;|[''"])\).*?>([^<]+)<'
    foreach ($m in [regex]::Matches($Html, $pattern)) {
        $id = $m.Groups[1].Value
        $title = [System.Net.WebUtility]::HtmlDecode($m.Groups[2].Value).Trim()
        if ([string]::IsNullOrWhiteSpace($title) -or $seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        $kb = $null
        if ($title -match '\((KB\d+)\)') { $kb = $Matches[1] }
        $rows.Add([pscustomobject]@{
                UpdateId = $id
                Title    = $title
                Kb       = $kb
            })
    }
    return $rows
}

function Test-WinMintQualityBReleaseTitle {
    param(
        [Parameter(Mandatory)] [string] $Title,
        [Parameter(Mandatory)] [string] $FamilyLabel,
        [Parameter(Mandatory)] [string] $Architecture
    )
    if ($Title -notmatch '(?i)Cumulative Update') { return $false }
    if ($Title -match '(?i)Preview|\.NET|Dynamic') { return $false }
    if ($Title -match '(?i)26H1') { return $false }
    if ($Title -notmatch [regex]::Escape("Version $FamilyLabel")) { return $false }
    $archToken = if ($Architecture -eq 'ARM64') { 'ARM64-based Systems' } else { 'x64-based Systems' }
    if ($Title -notmatch [regex]::Escape($archToken)) { return $false }
    if ($Architecture -eq 'ARM64' -and $Title -match '(?i)x64-based Systems') { return $false }
    return $true
}

function Select-WinMintQualityUpdate {
    param(
        [Parameter(Mandatory)] $Rows,
        [Parameter(Mandatory)] [string] $FamilyLabel,
        [Parameter(Mandatory)] [string] $Architecture
    )
    $candidates = @(
        $Rows |
            Where-Object { Test-WinMintQualityBReleaseTitle -Title $_.Title -FamilyLabel $FamilyLabel -Architecture $Architecture } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.Kb) }
    )
    if ($candidates.Count -lt 1) {
        throw "Catalog had no ARM64 $FamilyLabel Security (B-release) Cumulative Update"
    }
    $sorted = @(
        $candidates | Sort-Object {
            if ($_.Title -match '^(\d{4})-(\d{2})') { '{0}{1}' -f $Matches[1], $Matches[2] } else { '000000' }
        }, { $_.Kb } -Descending
    )
    return $sorted[0]
}

function Resolve-WinMintQualityUpdate {
    param(
        [Parameter(Mandatory)] [string] $Version,
        [Parameter(Mandatory)] [string] $Architecture,
        [Parameter(Mandatory)] [int] $ImageUbr,
        [Parameter(Mandatory)] [string] $SearchHtml,
        [Parameter(Mandatory)] [string] $DetailsHtml
    )
    $train = Get-WinMintQualityTrain -Version $Version -Architecture $Architecture
    $rows = ConvertFrom-WinMintCatalogSearchHtml -Html $SearchHtml
    $picked = Select-WinMintQualityUpdate -Rows $rows -FamilyLabel $train.Label -Architecture $train.Architecture
    $packageUbr = ConvertFrom-WinMintCatalogUbr -Text $DetailsHtml -Family $train.Family
    return [pscustomobject]@{
        Skipped      = $packageUbr -le $ImageUbr
        Kb           = $picked.Kb
        Title        = $picked.Title
        UpdateId     = $picked.UpdateId
        Family       = $train.Family
        Label        = $train.Label
        Architecture = $train.Architecture
        Query        = $train.Query
        ImageUbr     = $ImageUbr
        PackageUbr   = $packageUbr
        DetailsHtml  = $DetailsHtml
    }
}

function Invoke-WinMintQualityCatalogResolve {
    param(
        [Parameter(Mandatory)] [string] $Version,
        [Parameter(Mandatory)] [string] $Architecture,
        [Parameter(Mandatory)] [int] $ImageUbr
    )
    $train = Get-WinMintQualityTrain -Version $Version -Architecture $Architecture
    $searchHtml = Invoke-WinMintCatalogSearchHtml -Query "$($train.Query) ARM64-based Systems"
    $picked = Select-WinMintQualityUpdate `
        -Rows (ConvertFrom-WinMintCatalogSearchHtml -Html $searchHtml) `
        -FamilyLabel $train.Label `
        -Architecture $train.Architecture
    $detailsHtml = Invoke-WinMintCatalogDetailsHtml -UpdateId $picked.UpdateId
    return Resolve-WinMintQualityUpdate `
        -Version $Version `
        -Architecture $Architecture `
        -ImageUbr $ImageUbr `
        -SearchHtml $searchHtml `
        -DetailsHtml $detailsHtml
}

function ConvertFrom-WinMintCatalogUbr {
    param(
        [Parameter(Mandatory)] [string] $Text,
        [Parameter(Mandatory)] [int] $Family
    )
    $hits = [regex]::Matches($Text, "$Family\.(\d{3,5})")
    if ($hits.Count -lt 1) {
        throw "Catalog details missing OS build $Family.<ubr>"
    }
    $best = 0
    foreach ($h in $hits) {
        $n = [int]$h.Groups[1].Value
        if ($n -gt $best) { $best = $n }
    }
    return $best
}

function ConvertFrom-WinMintCatalogDownloadDialog {
    param([Parameter(Mandatory)] [string] $Text)
    # Catalog JS often escapes slashes; payload host moved to dl.delivery.mp.microsoft.com.
    $normalized = $Text.Replace('\/', '/')
    $urls = @(
        [regex]::Matches($normalized, "https?://[^'""\s<>]+") |
            ForEach-Object { $_.Value.TrimEnd('\', ',', ';') } |
            Select-Object -Unique |
            Where-Object { Test-WinMintDownloadWindowsupdateUri -Uri $_ }
    )
    if ($urls.Count -lt 1) {
        throw 'Catalog DownloadDialog returned no Catalog payload URL (download.windowsupdate.com or dl.delivery.mp.microsoft.com)'
    }
    return $urls
}

function ConvertFrom-WinMintCatalogCheckpointKb {
    param(
        [Parameter(Mandatory)] [string] $Text,
        [Parameter(Mandatory)] [string] $TargetKb
    )
    $kbs = [System.Collections.Generic.List[string]]::new()
    if ($Text -notmatch '(?i)checkpoint') { return @() }
    foreach ($m in [regex]::Matches($Text, '(KB\d+)')) {
        $kb = $m.Groups[1].Value
        if ($kb -eq $TargetKb) { continue }
        if ($kbs -notcontains $kb) { $kbs.Add($kb) }
    }
    return @($kbs)
}

function Test-WinMintRollupFixPresent {
    param(
        [Parameter(Mandatory)] [string] $GetPackagesText,
        [Parameter(Mandatory)] [int] $Family,
        [Parameter(Mandatory)] [int] $Ubr,
        [Parameter(Mandatory)] [string] $Architecture
    )
    $arch = $Architecture.ToLowerInvariant()
    $pattern = "(?im)^Package Identity\s*:\s*Package_for_RollupFix~\w+~$arch~~$Family\.$Ubr\."
    if ($GetPackagesText -notmatch $pattern) {
        throw "DISM /Get-Packages missing RollupFix ${Family}.${Ubr} ($Architecture)"
    }
}

function Test-WinMintDownloadWindowsupdateUri {
    param([string] $Uri)
    $parsed = $null
    if (-not [System.Uri]::TryCreate($Uri, [System.UriKind]::Absolute, [ref]$parsed)) { return $false }
    if ($parsed.Scheme -notin @('http', 'https')) { return $false }
    # Catalog DownloadDialog (2026): files[].url is catalog.sf.dl.delivery.mp.microsoft.com, not WU.
    return $parsed.Host -match '(?i)(^|\.)download\.windowsupdate\.com$' -or
        $parsed.Host -match '(?i)(^|\.)dl\.delivery\.mp\.microsoft\.com$'
}

function Save-WinMintCatalogPayload {
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [Parameter(Mandatory)] [string] $Destination
    )
    if (-not (Test-WinMintDownloadWindowsupdateUri -Uri $Uri)) {
        throw "Quality download host is not a Catalog payload CDN: $Uri"
    }
    $dir = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force }
    $bitsadmin = Join-Path $env:SystemRoot 'System32\bitsadmin.exe'
    if (-not (Test-Path -LiteralPath $bitsadmin)) {
        throw "bitsadmin.exe missing; cannot BITS-fetch Catalog payload"
    }
    $job = 'WinMintQuality-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    & $bitsadmin /transfer $job /download /priority FOREGROUND $Uri $Destination | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Destination)) {
        throw "BITS download failed ($LASTEXITCODE): $Uri"
    }
}

function Expand-WinMintQualitySsu {
    param(
        [Parameter(Mandatory)] [string] $MsuPath,
        [Parameter(Mandatory)] [string] $Destination
    )
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $expand = Join-Path $env:SystemRoot 'System32\expand.exe'
    if (-not (Test-Path -LiteralPath $expand)) { throw 'expand.exe missing' }
    & $expand $MsuPath -F:* $Destination | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "expand.exe failed ($LASTEXITCODE): $MsuPath"
    }
    $ssu = @(Get-ChildItem -LiteralPath $Destination -Filter 'SSU-*.cab' -File -ErrorAction SilentlyContinue)
    if ($ssu.Count -lt 1) {
        foreach ($cab in @(Get-ChildItem -LiteralPath $Destination -Filter '*.cab' -File)) {
            $inner = Join-Path $Destination ($cab.BaseName + '-inner')
            New-Item -ItemType Directory -Force -Path $inner | Out-Null
            & $expand $cab.FullName -F:* $inner | Out-Null
            $ssu += @(Get-ChildItem -LiteralPath $inner -Filter 'SSU-*.cab' -File -ErrorAction SilentlyContinue)
        }
    }
    if ($ssu.Count -lt 1) {
        throw "Combined LCU missing SSU-*.cab after expand: $MsuPath"
    }
    return [string]$ssu[0].FullName
}

function Find-WinMintQualityBootStl {
    param([Parameter(Mandatory)] [string] $ExtractDir)
    $hit = Get-ChildItem -LiteralPath $ExtractDir -Recurse -Filter 'boot.stl' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $hit) { return $null }
    return [string]$hit.FullName
}

function Invoke-WinMintDismAddPackage {
    param(
        [Parameter(Mandatory)] [string] $MountDir,
        [Parameter(Mandatory)] [string] $PackagePath
    )
    if (-not (Test-Path -LiteralPath $PackagePath)) {
        throw "Quality package missing: $PackagePath"
    }
    Write-Output "DISM /Add-Package $PackagePath"
    & dism.exe /English /Image:$MountDir /Add-Package /PackagePath:$PackagePath
    if ($LASTEXITCODE -ne 0) {
        throw "DISM /Add-Package failed ($LASTEXITCODE): $PackagePath"
    }
}

function Get-WinMintQualityPackageLeafPath {
    param(
        [Parameter(Mandatory)] [string] $PackageDir,
        [Parameter(Mandatory)] [ValidateSet('boot', 'winre')] [string] $Kind
    )
    return Join-Path $PackageDir "$Kind.packages"
}

function Get-WinMintQualityPackageLeaf {
    param(
        [Parameter(Mandatory)] [string] $PackageDir,
        [Parameter(Mandatory)] [ValidateSet('boot', 'winre')] [string] $Kind
    )
    $path = Get-WinMintQualityPackageLeafPath -PackageDir $PackageDir -Kind $Kind
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @()
    }
    return @(
        Get-Content -LiteralPath $path -Encoding utf8 |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Write-WinMintQualityPackageLeaf {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)] [string] $PackageDir,
        [Parameter(Mandatory)] [ValidateSet('boot', 'winre')] [string] $Kind,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Leaf
    )
    New-Item -ItemType Directory -Force -Path $PackageDir | Out-Null
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @($Leaf)) {
        if ([string]::IsNullOrWhiteSpace($item)) { continue }
        $name = $item.Trim()
        if ($name -match '[\\/]' -or $name -eq '.' -or $name -eq '..') {
            throw "Quality package leaf must be a filename: $name"
        }
        $names.Add($name)
    }
    Set-Content -LiteralPath (Get-WinMintQualityPackageLeafPath -PackageDir $PackageDir -Kind $Kind) `
        -Value @($names) -Encoding utf8
}

function Invoke-WinMintCatalogSearchHtml {
    param([Parameter(Mandatory)] [string] $Query)
    $uri = 'https://www.catalog.update.microsoft.com/Search.aspx?q=' + [uri]::EscapeDataString($Query)
    try {
        return (Invoke-WebRequest -Uri $uri -UseBasicParsing).Content
    }
    catch {
        throw "Catalog search failed (host offline or Catalog down): $($_.Exception.Message)"
    }
}

function Invoke-WinMintCatalogDetailsHtml {
    param([Parameter(Mandatory)] [string] $UpdateId)
    $uri = 'https://www.catalog.update.microsoft.com/ScopedViewInline.aspx?updateid=' + [uri]::EscapeDataString($UpdateId)
    try {
        return (Invoke-WebRequest -Uri $uri -UseBasicParsing).Content
    }
    catch {
        throw "Catalog details failed: $($_.Exception.Message)"
    }
}

function Invoke-WinMintCatalogDownloadDialog {
    param([Parameter(Mandatory)] [string] $UpdateId)
    $payload = 'updateIDs=' + [uri]::EscapeDataString(
        ('[{{"size":0,"languages":"","uidInfo":"{0}","updateID":"{0}"}}]' -f $UpdateId))
    try {
        $resp = Invoke-WebRequest -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' `
            -Method POST -Body $payload -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing
        return $resp.Content
    }
    catch {
        throw "Catalog DownloadDialog failed: $($_.Exception.Message)"
    }
}

function Select-WinMintDynamicUpdate {
    param(
        [Parameter(Mandatory)] $Rows,
        [Parameter(Mandatory)] [string] $FamilyLabel,
        [Parameter(Mandatory)] [string] $Architecture,
        [Parameter(Mandatory)] [ValidateSet('Setup', 'SafeOS')] [string] $Kind,
        [string] $MonthPrefix
    )
    $archToken = 'ARM64-based Systems'
    if ($Architecture -ne 'ARM64') { $archToken = 'x64-based Systems' }
    $candidates = @(
        $Rows | Where-Object {
            $t = [string]$_.Title
            if ($t -match '(?i)Preview') { return $false }
            if ($t -notmatch [regex]::Escape("Version $FamilyLabel")) { return $false }
            if ($t -notmatch [regex]::Escape($archToken)) { return $false }
            if ($Kind -eq 'SafeOS') {
                if ($t -notmatch '(?i)Safe OS Dynamic Update') { return $false }
            }
            else {
                if ($t -notmatch '(?i)Dynamic Update') { return $false }
                if ($t -match '(?i)Safe OS') { return $false }
            }
            if ($MonthPrefix -and $t -notmatch [regex]::Escape($MonthPrefix)) { return $false }
            return $true
        }
    )
    if ($candidates.Count -lt 1) { return $null }
    return @($candidates | Sort-Object Title -Descending)[0]
}

function Select-WinMintCatalogMsuUrl {
    param([Parameter(Mandatory)] $Urls)
    $msu = @($Urls | Where-Object { $_ -match '(?i)\.msu(\?|$)' })
    if ($msu.Count -ge 1) { return [string]$msu[0] }
    $cab = @($Urls | Where-Object { $_ -match '(?i)\.cab(\?|$)' })
    if ($cab.Count -ge 1) { return [string]$cab[0] }
    throw 'Catalog download had no .msu/.cab payload'
}

function Get-WinMintCatalogPayload {
    param(
        [Parameter(Mandatory)] [string] $UpdateId,
        [Parameter(Mandatory)] [string] $CacheRoot,
        [Parameter(Mandatory)] [string] $Kb,
        [Parameter(Mandatory)] [string] $Architecture,
        [Parameter(Mandatory)] [string] $StagingDir
    )
    $cached = Resolve-WinMintCachedQualityFile -CacheRoot $CacheRoot -Kb $Kb -Architecture $Architecture
    if ($cached) { return $cached }
    $dialog = Invoke-WinMintCatalogDownloadDialog -UpdateId $UpdateId
    $url = Select-WinMintCatalogMsuUrl -Urls (ConvertFrom-WinMintCatalogDownloadDialog -Text $dialog)
    $leaf = [IO.Path]::GetFileName(([uri]$url).AbsolutePath)
    if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf = "$Kb.msu" }
    $tmp = Join-Path $StagingDir $leaf
    Save-WinMintCatalogPayload -Uri $url -Destination $tmp
    return (Save-WinMintQualityCacheFile -CacheRoot $CacheRoot -Kb $Kb -Architecture $Architecture -SourcePath $tmp).Path
}

function Resolve-WinMintCachedQualityFile {
    param(
        [Parameter(Mandatory)] [string] $CacheRoot,
        [Parameter(Mandatory)] [string] $Kb,
        [Parameter(Mandatory)] [string] $Architecture,
        [string] $Sha256
    )
    $arch = $Architecture.ToLowerInvariant()
    $kbLeaf = $Kb.ToUpperInvariant()
    if (-not [string]::IsNullOrWhiteSpace($Sha256)) {
        $dir = Join-Path $CacheRoot "$kbLeaf\$arch\$($Sha256.ToLowerInvariant())"
        $hit = Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in '.msu', '.cab' } |
            Select-Object -First 1
        if ($null -ne $hit) { return [string]$hit.FullName }
        return $null
    }
    $base = Join-Path $CacheRoot "$kbLeaf\$arch"
    if (-not (Test-Path -LiteralPath $base)) { return $null }
    $hit = Get-ChildItem -LiteralPath $base -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.msu', '.cab' } |
        Select-Object -First 1
    if ($null -eq $hit) { return $null }
    return [string]$hit.FullName
}

function Save-WinMintQualityCacheFile {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)] [string] $CacheRoot,
        [Parameter(Mandatory)] [string] $Kb,
        [Parameter(Mandatory)] [string] $Architecture,
        [Parameter(Mandatory)] [string] $SourcePath
    )
    $sha = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $arch = $Architecture.ToLowerInvariant()
    $dir = Join-Path $CacheRoot "$($Kb.ToUpperInvariant())\$arch\$sha"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dest = Join-Path $dir (Split-Path -Leaf $SourcePath)
    if (-not (Test-Path -LiteralPath $dest)) {
        Copy-Item -LiteralPath $SourcePath -Destination $dest -Force
    }
    return [pscustomobject]@{ Path = $dest; Sha256 = $sha }
}
