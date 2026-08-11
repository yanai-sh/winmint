#requires -Version 7.6
<#
.SYNOPSIS
  Prove live winget/scoop catalog ids (winget download / scoop archive download) and write config/packages.proof.json.
.NOTES
  Maintainer gate only — never part of `just check`. Needs network + native ARM64 + winget.
  Offline receipt test in just check enforces freshness. Validity = download prove + receipt.
  Winget: `winget download` (App Installer has no install --dry-run). Scoop: manifest + archive download.
#>
param(
    [string] $CatalogPath = '',
    [string] $Architecture = 'arm64',
    [switch] $SelfCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
    $CatalogPath = Join-Path $repoRoot 'config\packages.json'
}

$script:ScoopBucketRaw = @{
    main   = 'https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket'
    extras = 'https://raw.githubusercontent.com/ScoopInstaller/Extras/master/bucket'
}

$script:ProveEntries = [System.Collections.Generic.List[object]]::new()

function Get-ScoopManifestUri {
    param(
        [Parameter(Mandatory)][string] $Id,
        [string] $Bucket
    )
    $b = if ([string]::IsNullOrWhiteSpace($Bucket)) { 'main' } else { $Bucket.Trim().ToLowerInvariant() }
    if (-not $script:ScoopBucketRaw.ContainsKey($b)) {
        throw "unknown scoop bucket '$Bucket' (supported: $($script:ScoopBucketRaw.Keys -join ', '))"
    }
    return "$($script:ScoopBucketRaw[$b])/$Id.json"
}

function Get-JsonProp {
    param(
        [Parameter(Mandatory)][psobject] $Object,
        [Parameter(Mandatory)][string] $Name
    )
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Test-ScoopArm64Url {
    param([Parameter(Mandatory)][psobject] $Manifest)
    $arch = Get-JsonProp -Object $Manifest -Name 'architecture'
    if ($null -ne $arch) {
        foreach ($name in @('arm64', 'aarch64')) {
            $node = Get-JsonProp -Object $arch -Name $name
            if ($null -ne $node) {
                $url = Get-JsonProp -Object $node -Name 'url'
                if (-not [string]::IsNullOrWhiteSpace([string]$url)) {
                    return $url
                }
            }
        }
        return $null
    }
    $universal = Get-JsonProp -Object $Manifest -Name 'url'
    if (-not [string]::IsNullOrWhiteSpace([string]$universal)) {
        return $universal
    }
    return $null
}

function Get-FirstUrl {
    param($Url)
    if ($null -eq $Url) { return $null }
    if ($Url -is [System.Array]) {
        if ($Url.Count -eq 0) { return $null }
        return [string]$Url[0]
    }
    return [string]$Url
}

function Get-FileSha256Hex {
    param([Parameter(Mandatory)][string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ProveSetSha256Hex {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Entries)
    if ($null -eq $Entries -or $Entries.Count -eq 0) {
        $bytes = [byte[]]@()
    }
    else {
        [string[]]$lines = @(
            $Entries | ForEach-Object { "$($_.Source):$($_.Id)" }
        )
        [Array]::Sort($lines, [StringComparer]::Ordinal)
        $text = ($lines -join "`n") + "`n"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function Test-WingetId {
    param(
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][string] $Architecture
    )
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        throw 'winget not on PATH (install App Installer / use an ARM64 host with winget)'
    }
    # App Installer has no install --dry-run; download proves arch + installer fetch without installing.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("winmint-winget-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $out = & winget download --id $Id --exact --architecture $Architecture `
            --download-directory $tmp `
            --disable-interactivity --accept-package-agreements --accept-source-agreements 2>&1
        $code = $LASTEXITCODE
        if ($code -ne 0) {
            $tail = ($out | Out-String).Trim()
            if ($tail.Length -gt 240) { $tail = $tail.Substring(0, 240) + '…' }
            throw "winget download failed (exit $code): $tail"
        }
        $files = @(Get-ChildItem -LiteralPath $tmp -File -Recurse -ErrorAction SilentlyContinue)
        if ($files.Count -eq 0 -or ($files | Measure-Object -Property Length -Sum).Sum -le 0) {
            throw "winget download produced no files for $Id"
        }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-ScoopId {
    param(
        [Parameter(Mandatory)][string] $Id,
        [string] $Bucket,
        [Parameter(Mandatory)][string] $Architecture
    )
    $uri = Get-ScoopManifestUri -Id $Id -Bucket $Bucket
    $manifest = Invoke-RestMethod -Uri $uri -Method Get
    $urlRaw = Test-ScoopArm64Url -Manifest $manifest
    $url = Get-FirstUrl -Url $urlRaw
    if ($Architecture -eq 'arm64' -and [string]::IsNullOrWhiteSpace($url)) {
        throw "scoop manifest has no arm64/aarch64 (or universal) url: $uri"
    }
    if ([string]::IsNullOrWhiteSpace($url)) {
        throw "scoop manifest has no download url: $uri"
    }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("winmint-scoop-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $dest = Join-Path $tmp 'payload.bin'
        Invoke-WebRequest -Uri $url -OutFile $dest -MaximumRedirection 5
        if (-not (Test-Path -LiteralPath $dest) -or (Get-Item -LiteralPath $dest).Length -le 0) {
            throw "scoop download empty: $url"
        }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Write-PackagesProofReceipt {
    param(
        [Parameter(Mandatory)][string] $CatalogPath,
        [Parameter(Mandatory)][string] $Architecture,
        [Parameter(Mandatory)][string] $OsArch,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Entries
    )
    $receiptPath = Join-Path $repoRoot 'config\packages.proof.json'
    $wingetVer = (& winget --version 2>$null | Out-String).Trim()
    $entryRows = @(
        foreach ($e in ($Entries | Sort-Object @{ Expression = { $_.Source }; Ascending = $true }, @{ Expression = { $_.Id }; Ascending = $true })) {
            $row = [ordered]@{
                source = $e.Source
                id     = $e.Id
                method = $e.Method
            }
            if ($e.Source -eq 'scoop') { $row.bucket = $e.Bucket }
            [pscustomobject]$row
        }
    )
    $receipt = [ordered]@{
        schema         = 'winmint.packages.proof/v1'
        architecture   = $Architecture
        catalogSha256  = Get-FileSha256Hex -Path $CatalogPath
        proveSetSha256 = Get-ProveSetSha256Hex -Entries $Entries
        provenAtUtc    = [datetime]::UtcNow.ToString('o')
        host           = @{
            winget = $wingetVer
            osArch = $OsArch
        }
        entries        = $entryRows
    }
    $tmpReceipt = Join-Path $repoRoot 'config\packages.proof.json.tmp'
    $json = ($receipt | ConvertTo-Json -Depth 6) + "`n"
    [System.IO.File]::WriteAllText($tmpReceipt, $json)
    Move-Item -LiteralPath $tmpReceipt -Destination $receiptPath -Force
    Write-Output "wrote $receiptPath"
}

function Invoke-PackagesCheck {
    param(
        [Parameter(Mandatory)][string] $CatalogPath,
        [Parameter(Mandatory)][string] $Architecture
    )

    $arch = $Architecture.Trim().ToLowerInvariant()
    if ($arch -notin @('arm64', 'amd64', 'x64')) {
        throw "Architecture must be arm64 or amd64 (got '$Architecture')"
    }
    if ($arch -eq 'x64') { $arch = 'amd64' }

    $osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    if ($arch -eq 'arm64' -and $osArch -ne 'Arm64') {
        throw "packages-check for arm64 requires native ARM64 host (OSArchitecture=$osArch)"
    }

    if (-not (Test-Path -LiteralPath $CatalogPath)) {
        throw "catalog missing: $CatalogPath"
    }

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        throw 'winget not on PATH (install App Installer / use an ARM64 host with winget)'
    }

    Write-Output 'winget source update…'
    & winget source update --disable-interactivity 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Output "WARN winget source update exit $LASTEXITCODE — continuing; winget show must still pass"
    }

    $doc = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json
    if ($null -eq $doc.tools) {
        throw 'catalog has no tools object'
    }

    $failures = [System.Collections.Generic.List[string]]::new()
    $ok = 0
    $skipped = 0
    $script:ProveEntries.Clear()

    foreach ($prop in $doc.tools.PSObject.Properties) {
        $key = $prop.Name
        $row = $prop.Value
        $source = [string]$row.source
        $id = [string]$row.id
        $arches = @($row.architectures | ForEach-Object { [string]$_ })
        if ($true -eq (Get-JsonProp -Object $row -Name 'stub')) {
            $skipped++
            Write-Output "skip  $key ($id) — catalog stub (not published)"
            continue
        }
        if ($arches.Count -gt 0 -and ($arches -notcontains $arch)) {
            $skipped++
            Write-Output "skip  $key ($id) — no $arch in architectures"
            continue
        }

        try {
            switch ($source.ToLowerInvariant()) {
                'winget' {
                    Test-WingetId -Id $id -Architecture $arch
                    $script:ProveEntries.Add([pscustomobject]@{
                            Source = 'winget'
                            Id     = $id
                            Method = 'winget-download'
                            Bucket = $null
                        })
                    Write-Output "ok    winget $key ($id) $arch download"
                    $ok++
                }
                'scoop' {
                    $bucket = [string](Get-JsonProp -Object $row -Name 'scoopBucket')
                    $bucketLabel = if ([string]::IsNullOrWhiteSpace($bucket)) { 'main' } else { $bucket }
                    Test-ScoopId -Id $id -Bucket $bucket -Architecture $arch
                    $script:ProveEntries.Add([pscustomobject]@{
                            Source = 'scoop'
                            Id     = $id
                            Method = 'scoop-manifest-download'
                            Bucket = $bucketLabel
                        })
                    Write-Output "ok    scoop  $key ($id) bucket=$bucketLabel download"
                    $ok++
                }
                'store' {
                    $skipped++
                    Write-Output "skip  $key ($id) — store (not winget/scoop prove)"
                }
                default {
                    throw "unknown source '$source'"
                }
            }
        }
        catch {
            $msg = "FAIL  $key ($id) [$source]: $($_.Exception.Message)"
            $failures.Add($msg)
            Write-Output $msg
        }
    }

    Write-Output "packages-check: ok=$ok skipped=$skipped fail=$($failures.Count) arch=$arch catalog=$CatalogPath"
    if ($failures.Count -gt 0) {
        throw "packages-check failed ($($failures.Count)) — receipt not updated"
    }

    Write-PackagesProofReceipt -CatalogPath $CatalogPath -Architecture $arch -OsArch $osArch -Entries @($script:ProveEntries)
}

if ($SelfCheck) {
    # Offline: URI + arm64 URL extraction + prove-set hash (no network / winget).
    $uri = Get-ScoopManifestUri -Id 'starship' -Bucket 'main'
    if ($uri -notmatch '/starship\.json$') { throw "SelfCheck uri: $uri" }
    $extras = Get-ScoopManifestUri -Id 'komorebi' -Bucket 'extras'
    if ($extras -notmatch 'Extras/master/bucket/komorebi\.json$') { throw "SelfCheck extras: $extras" }

    $withArm = [pscustomobject]@{
        architecture = [pscustomobject]@{
            arm64 = [pscustomobject]@{ url = 'https://example.test/arm64.zip' }
        }
    }
    if ((Test-ScoopArm64Url -Manifest $withArm) -ne 'https://example.test/arm64.zip') {
        throw 'SelfCheck arm64 url miss'
    }
    $universal = [pscustomobject]@{ url = 'https://example.test/any.zip' }
    if ((Test-ScoopArm64Url -Manifest $universal) -ne 'https://example.test/any.zip') {
        throw 'SelfCheck universal url miss'
    }
    $amdOnly = [pscustomobject]@{
        architecture = [pscustomobject]@{
            '64bit' = [pscustomobject]@{ url = 'https://example.test/x64.zip' }
        }
    }
    if ($null -ne (Test-ScoopArm64Url -Manifest $amdOnly)) {
        throw 'SelfCheck should reject amd64-only'
    }

    # Must match C# PackagesProof.ProveSetSha256 for unsorted scoop:starship + winget:Git.MinGit
    $entries = @(
        [pscustomobject]@{ Source = 'scoop'; Id = 'starship' },
        [pscustomobject]@{ Source = 'winget'; Id = 'Git.MinGit' }
    )
    $hash = Get-ProveSetSha256Hex -Entries $entries
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $pinBytes = [System.Text.Encoding]::UTF8.GetBytes("scoop:starship`nwinget:Git.MinGit`n")
        $expected = ([System.BitConverter]::ToString($sha.ComputeHash($pinBytes)) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
    if ($hash -ne $expected) {
        throw "SelfCheck proveSetSha256 mismatch: got $hash expected $expected"
    }

    if (-not (Test-Path -LiteralPath $CatalogPath)) {
        throw "SelfCheck catalog missing: $CatalogPath"
    }
    $null = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json
    Write-Output 'SelfCheck ok'
    exit 0
}

Invoke-PackagesCheck -CatalogPath $CatalogPath -Architecture $Architecture
