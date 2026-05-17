#Requires -Version 7.3

<#
.SYNOPSIS
    TTL-bounded temp caches for expensive build intermediates (host driver export, MSI extracts,
    Cascadia Nerd Font TTFs after a successful GitHub download).
.NOTES
    Lives under %LOCALAPPDATA%\WinWS\cache\ alongside iso-stage. Default TTL 48h; maintenance
    runs on cache probes and from startup cleanup. Host-driver export uses a single-slot policy
    (one cached export per machine) to cap disk use; MSI bundle caches are keyed per MSI set.
    Cascadia cache is single-slot (replaces prior entry on publish) and skips GitHub + zip work.
#>

$script:WinWSIntermediatesCacheTtlHours = 48

function Get-WinWSBuildCacheRoot {
    return (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WinWS\cache')
}

function Get-WinWSCacheKeyHex {
    param([Parameter(Mandatory)][string]$Fingerprint)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Fingerprint))
    }
    finally {
        $sha.Dispose()
    }
    return ([System.BitConverter]::ToString($bytes) -replace '-', '').Substring(0, 24).ToLowerInvariant()
}

function Test-WinWSIntermediatesCacheMarkerFileFresh {
    param([Parameter(Mandatory)][string]$MarkerJsonPath)
    if (-not (Test-Path -LiteralPath $MarkerJsonPath)) { return $false }
    try {
        $meta = Get-Content -LiteralPath $MarkerJsonPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $saved = [datetime]::Parse([string]$meta.SavedUtc, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return (([datetime]::UtcNow - $saved).TotalHours -lt $script:WinWSIntermediatesCacheTtlHours)
    }
    catch {
        return $false
    }
}

function Remove-WinWSIntermediatesCacheTree {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    }
    catch {
        LogVerbose "IntermediatesCache: could not remove '$Path': $($_.Exception.Message)"
    }
}

function Invoke-WinWSDriverMsiBundleCacheMaintenance {
    $root = Join-Path (Get-WinWSBuildCacheRoot) 'driver-msi-bundle'
    if (-not (Test-Path -LiteralPath $root)) { return }
    foreach ($json in @(Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        if (-not (Test-WinWSIntermediatesCacheMarkerFileFresh -MarkerJsonPath $json.FullName)) {
            $key = [IO.Path]::GetFileNameWithoutExtension($json.Name)
            Remove-WinWSIntermediatesCacheTree -Path (Join-Path $root $key)
            Remove-Item -LiteralPath $json.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $marker = Join-Path $root ($dir.Name + '.json')
        if (-not (Test-Path -LiteralPath $marker)) {
            Remove-WinWSIntermediatesCacheTree -Path $dir.FullName
        }
    }
}

function Invoke-WinWSDriverMsiSingleCacheMaintenance {
    $root = Join-Path (Get-WinWSBuildCacheRoot) 'driver-msi-single'
    if (-not (Test-Path -LiteralPath $root)) { return }
    foreach ($json in @(Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        if (-not (Test-WinWSIntermediatesCacheMarkerFileFresh -MarkerJsonPath $json.FullName)) {
            $key = [IO.Path]::GetFileNameWithoutExtension($json.Name)
            Remove-WinWSIntermediatesCacheTree -Path (Join-Path $root $key)
            Remove-Item -LiteralPath $json.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $marker = Join-Path $root ($dir.Name + '.json')
        if (-not (Test-Path -LiteralPath $marker)) {
            Remove-WinWSIntermediatesCacheTree -Path $dir.FullName
        }
    }
}

function Invoke-WinWSHostDriverExportCacheMaintenance {
    $root = Join-Path (Get-WinWSBuildCacheRoot) 'host-drivers'
    if (-not (Test-Path -LiteralPath $root)) { return }
    foreach ($json in @(Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        if (-not (Test-WinWSIntermediatesCacheMarkerFileFresh -MarkerJsonPath $json.FullName)) {
            $key = [IO.Path]::GetFileNameWithoutExtension($json.Name)
            Remove-WinWSIntermediatesCacheTree -Path (Join-Path $root $key)
            Remove-Item -LiteralPath $json.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $marker = Join-Path $root ($dir.Name + '.json')
        if (-not (Test-Path -LiteralPath $marker)) {
            Remove-WinWSIntermediatesCacheTree -Path $dir.FullName
        }
    }
}

function Invoke-WinWSAllBuildCachesMaintenance {
    Invoke-WinWSIsoStageCacheMaintenance
    Invoke-WinWSHostDriverExportCacheMaintenance
    Invoke-WinWSDriverMsiBundleCacheMaintenance
    Invoke-WinWSDriverMsiSingleCacheMaintenance
    Invoke-WinWSCascadiaNerdFontCacheMaintenance
}

function Get-WinWSDriverMsiSetFingerprint {
    param([Parameter(Mandatory)][System.IO.FileInfo[]]$MsiFiles)
    $sorted = @($MsiFiles | Sort-Object -Property FullName)
    return (($sorted | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" }) -join ';')
}

function Get-WinWSDriverMsiBundleCacheHit {
    param([Parameter(Mandatory)][string]$Fingerprint)
    Invoke-WinWSDriverMsiBundleCacheMaintenance
    if ([string]::IsNullOrWhiteSpace($Fingerprint)) { return $null }
    $key = Get-WinWSCacheKeyHex -Fingerprint $Fingerprint
    $root = Join-Path (Get-WinWSBuildCacheRoot) 'driver-msi-bundle'
    $markerPath = Join-Path $root "$key.json"
    $bundleDir = Join-Path $root $key
    if (-not (Test-Path -LiteralPath $markerPath)) { return $null }
    if (-not (Test-WinWSIntermediatesCacheMarkerFileFresh -MarkerJsonPath $markerPath)) {
        Remove-WinWSIntermediatesCacheTree -Path $bundleDir
        Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
        return $null
    }
    try {
        $meta = Get-Content -LiteralPath $markerPath -Raw -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        return $null
    }
    if ([string]$meta.Fingerprint -ne $Fingerprint) { return $null }
    if (-not (Test-Path -LiteralPath $bundleDir -PathType Container)) { return $null }
    $infCount = (Get-ChildItem -LiteralPath $bundleDir -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($infCount -lt 1) { return $null }
    return $bundleDir
}

function Publish-WinWSDriverMsiBundleCache {
    param(
        [Parameter(Mandatory)][string]$Fingerprint,
        [Parameter(Mandatory)][string]$SourceParentDir
    )
    if ([string]::IsNullOrWhiteSpace($Fingerprint)) { return }
    if (-not (Test-Path -LiteralPath $SourceParentDir -PathType Container)) { return }
    $infCount = (Get-ChildItem -LiteralPath $SourceParentDir -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($infCount -lt 1) { return }

    $key = $null
    try {
        Invoke-WinWSDriverMsiBundleCacheMaintenance
        $key = Get-WinWSCacheKeyHex -Fingerprint $Fingerprint
        $root = Join-Path (Get-WinWSBuildCacheRoot) 'driver-msi-bundle'
        if (-not (Test-Path -LiteralPath $root)) {
            $null = New-Item -ItemType Directory -Path $root -Force -ErrorAction Stop
        }
        $markerPath = Join-Path $root "$key.json"
        $bundleDir = Join-Path $root $key
        if (Test-Path -LiteralPath $bundleDir) { Remove-WinWSIntermediatesCacheTree -Path $bundleDir }
        if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue }
        $null = New-Item -ItemType Directory -Path $bundleDir -Force -ErrorAction Stop
        Invoke-RobocopyChecked -Source $SourceParentDir -Dest $bundleDir -UserFacingMessage 'Saving temp cache of driver MSI extracts…'
        $marker = [ordered]@{
            Schema      = 2
            Kind        = 'driver-msi-bundle'
            Fingerprint = $Fingerprint
            SavedUtc    = [datetime]::UtcNow.ToString('o')
        }
        $marker | ConvertTo-Json -Compress | Set-Content -LiteralPath $markerPath -Encoding UTF8
    }
    catch {
        LogVerbose "driver-msi-bundle cache publish skipped: $($_.Exception.Message)"
        if ($null -ne $key) {
            $root = Join-Path (Get-WinWSBuildCacheRoot) 'driver-msi-bundle'
            $bundleDir = Join-Path $root $key
            $markerPath = Join-Path $root "$key.json"
            if (Test-Path -LiteralPath $bundleDir) { Remove-WinWSIntermediatesCacheTree -Path $bundleDir }
            if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Get-WinWSDriverMsiSingleExtractCacheHit {
    param([Parameter(Mandatory)][string]$MsiPath)
    Invoke-WinWSDriverMsiSingleCacheMaintenance
    if (-not (Test-Path -LiteralPath $MsiPath)) { return $null }
    $item = Get-Item -LiteralPath $MsiPath -ErrorAction Stop
    $fingerprint = "$($item.FullName)|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"
    $key = Get-WinWSCacheKeyHex -Fingerprint $fingerprint
    $root = Join-Path (Get-WinWSBuildCacheRoot) 'driver-msi-single'
    $markerPath = Join-Path $root "$key.json"
    $payloadDir = Join-Path $root $key
    if (-not (Test-Path -LiteralPath $markerPath)) { return $null }
    if (-not (Test-WinWSIntermediatesCacheMarkerFileFresh -MarkerJsonPath $markerPath)) {
        Remove-WinWSIntermediatesCacheTree -Path $payloadDir
        Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
        return $null
    }
    try {
        $meta = Get-Content -LiteralPath $markerPath -Raw -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        return $null
    }
    if ([string]$meta.Fingerprint -ne $fingerprint) { return $null }
    if (-not (Test-Path -LiteralPath $payloadDir -PathType Container)) { return $null }
    $infCount = (Get-ChildItem -LiteralPath $payloadDir -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($infCount -lt 1) { return $null }
    return $payloadDir
}

function Publish-WinWSDriverMsiSingleExtractCache {
    param(
        [Parameter(Mandatory)][string]$MsiPath,
        [Parameter(Mandatory)][string]$SourceDir
    )
    if (-not (Test-Path -LiteralPath $MsiPath)) { return }
    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) { return }
    $infCount = (Get-ChildItem -LiteralPath $SourceDir -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($infCount -lt 1) { return }

    $item = Get-Item -LiteralPath $MsiPath -ErrorAction Stop
    $fingerprint = "$($item.FullName)|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"
    $key = $null
    try {
        Invoke-WinWSDriverMsiSingleCacheMaintenance
        $key = Get-WinWSCacheKeyHex -Fingerprint $fingerprint
        $root = Join-Path (Get-WinWSBuildCacheRoot) 'driver-msi-single'
        if (-not (Test-Path -LiteralPath $root)) {
            $null = New-Item -ItemType Directory -Path $root -Force -ErrorAction Stop
        }
        $markerPath = Join-Path $root "$key.json"
        $payloadDir = Join-Path $root $key
        if (Test-Path -LiteralPath $payloadDir) { Remove-WinWSIntermediatesCacheTree -Path $payloadDir }
        if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue }
        $null = New-Item -ItemType Directory -Path $payloadDir -Force -ErrorAction Stop
        Invoke-RobocopyChecked -Source $SourceDir -Dest $payloadDir -UserFacingMessage 'Saving temp cache of driver MSI extract…'
        $marker = [ordered]@{
            Schema      = 2
            Kind        = 'driver-msi-single'
            Fingerprint = $fingerprint
            SavedUtc    = [datetime]::UtcNow.ToString('o')
        }
        $marker | ConvertTo-Json -Compress | Set-Content -LiteralPath $markerPath -Encoding UTF8
    }
    catch {
        LogVerbose "driver-msi-single cache publish skipped: $($_.Exception.Message)"
        if ($null -ne $key) {
            $root = Join-Path (Get-WinWSBuildCacheRoot) 'driver-msi-single'
            $payloadDir = Join-Path $root $key
            $markerPath = Join-Path $root "$key.json"
            if (Test-Path -LiteralPath $payloadDir) { Remove-WinWSIntermediatesCacheTree -Path $payloadDir }
            if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Get-WinWSHostDriverExportFingerprint {
    $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $machine = [Environment]::MachineName
    return "${machine}|$($cv.CurrentBuild).$($cv.UBR)|$($cv.DisplayVersion)"
}

function Get-WinWSHostDriverExportCacheHit {
    Invoke-WinWSHostDriverExportCacheMaintenance
    $fingerprint = Get-WinWSHostDriverExportFingerprint
    $key = Get-WinWSCacheKeyHex -Fingerprint $fingerprint
    $root = Join-Path (Get-WinWSBuildCacheRoot) 'host-drivers'
    $markerPath = Join-Path $root "$key.json"
    $payloadDir = Join-Path $root $key
    if (-not (Test-Path -LiteralPath $markerPath)) { return $null }
    if (-not (Test-WinWSIntermediatesCacheMarkerFileFresh -MarkerJsonPath $markerPath)) {
        Remove-WinWSIntermediatesCacheTree -Path $payloadDir
        Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
        return $null
    }
    try {
        $meta = Get-Content -LiteralPath $markerPath -Raw -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        return $null
    }
    if ([string]$meta.Fingerprint -ne $fingerprint) { return $null }
    if (-not (Test-Path -LiteralPath $payloadDir -PathType Container)) { return $null }
    $infCount = (Get-ChildItem -LiteralPath $payloadDir -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($infCount -lt 1) { return $null }
    return $payloadDir
}

function Publish-WinWSHostDriverExportCache {
    param([Parameter(Mandatory)][string]$SourceDir)
    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) { return }
    $infCount = (Get-ChildItem -LiteralPath $SourceDir -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($infCount -lt 1) { return }

    $fingerprint = Get-WinWSHostDriverExportFingerprint
    $key = Get-WinWSCacheKeyHex -Fingerprint $fingerprint
    $root = Join-Path (Get-WinWSBuildCacheRoot) 'host-drivers'
    try {
        if (-not (Test-Path -LiteralPath $root)) {
            $null = New-Item -ItemType Directory -Path $root -Force -ErrorAction Stop
        }
        else {
            foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
                Remove-WinWSIntermediatesCacheTree -Path $d.FullName
            }
            foreach ($f in @(Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
            }
        }
        $markerPath = Join-Path $root "$key.json"
        $payloadDir = Join-Path $root $key
        $null = New-Item -ItemType Directory -Path $payloadDir -Force -ErrorAction Stop
        Invoke-RobocopyChecked -Source $SourceDir -Dest $payloadDir -UserFacingMessage 'Saving temp cache of exported host drivers…'
        $marker = [ordered]@{
            Schema      = 2
            Kind        = 'host-drivers'
            Fingerprint = $fingerprint
            SavedUtc    = [datetime]::UtcNow.ToString('o')
        }
        $marker | ConvertTo-Json -Compress | Set-Content -LiteralPath $markerPath -Encoding UTF8
    }
    catch {
        LogVerbose "host-drivers cache publish skipped: $($_.Exception.Message)"
        if (Test-Path -LiteralPath $root) {
            foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
                if ($d.Name -eq $key) { Remove-WinWSIntermediatesCacheTree -Path $d.FullName }
            }
            $orphanMarker = Join-Path $root "$key.json"
            if (Test-Path -LiteralPath $orphanMarker) { Remove-Item -LiteralPath $orphanMarker -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Invoke-WinWSCascadiaNerdFontCacheMaintenance {
    $dir = Join-Path (Get-WinWSBuildCacheRoot) 'cascadia-nerdfont'
    if (-not (Test-Path -LiteralPath $dir)) { return }
    $marker = Join-Path $dir 'marker.json'
    if (-not (Test-Path -LiteralPath $marker)) {
        Remove-WinWSIntermediatesCacheTree -Path $dir
        return
    }
    if (-not (Test-WinWSIntermediatesCacheMarkerFileFresh -MarkerJsonPath $marker)) {
        Remove-WinWSIntermediatesCacheTree -Path $dir
    }
}

function Get-WinWSCascadiaNerdFontCachePayloadDir {
    param([Parameter(Mandatory)][string]$CacheRootDir)
    return (Join-Path $CacheRootDir 'ttf')
}

function Get-WinWSCascadiaNerdFontCacheHit {
    Invoke-WinWSCascadiaNerdFontCacheMaintenance
    $dir = Join-Path (Get-WinWSBuildCacheRoot) 'cascadia-nerdfont'
    $marker = Join-Path $dir 'marker.json'
    if (-not (Test-Path -LiteralPath $marker)) { return $null }
    if (-not (Test-WinWSIntermediatesCacheMarkerFileFresh -MarkerJsonPath $marker)) {
        Remove-WinWSIntermediatesCacheTree -Path $dir
        return $null
    }
    $ttfDir = Get-WinWSCascadiaNerdFontCachePayloadDir -CacheRootDir $dir
    if (-not (Test-Path -LiteralPath $ttfDir -PathType Container)) { return $null }
    $hasNf = @(Get-ChildItem -LiteralPath $ttfDir -Filter '*NF*.ttf' -File -ErrorAction SilentlyContinue).Count -ge 1
    if (-not $hasNf) { return $null }
    return $dir
}

function Restore-WinWSCascadiaNerdFontFromCache {
    param(
        [Parameter(Mandatory)][string]$FontDir,
        [Parameter(Mandatory)][string]$CacheRootDir
    )
    $ttfDir = Get-WinWSCascadiaNerdFontCachePayloadDir -CacheRootDir $CacheRootDir
    $marker = Join-Path $CacheRootDir 'marker.json'
    $meta = Get-Content -LiteralPath $marker -Raw -ErrorAction Stop | ConvertFrom-Json
    $null = New-Item -Path $FontDir -ItemType Directory -Force
    Get-ChildItem -LiteralPath $ttfDir -Filter '*NF*.ttf' -File -ErrorAction Stop |
        Copy-Item -Destination $FontDir -Force
    Add-WinWSManifestPayload -Name 'Cascadia Code (Nerd Font)' -SourceUrl ([string]$meta.SourceUrl) `
        -Version ([string]$meta.Version) -Sha256 ([string]$meta.Sha256) -SizeBytes ([long]$meta.SizeBytes)
}

function Publish-WinWSCascadiaNerdFontCache {
    param(
        [Parameter(Mandatory)][string]$FontDir,
        [Parameter(Mandatory)][string]$TagName,
        [Parameter(Mandatory)][string]$AssetName,
        [Parameter(Mandatory)][string]$SourceUrl,
        [Parameter(Mandatory)][string]$Sha256,
        [Parameter(Mandatory)][long]$SizeBytes
    )
    $nf = @(Get-ChildItem -LiteralPath $FontDir -Filter '*NF*.ttf' -File -ErrorAction SilentlyContinue)
    if ($nf.Count -lt 1) { return }

    $dir = Join-Path (Get-WinWSBuildCacheRoot) 'cascadia-nerdfont'
    try {
        if (Test-Path -LiteralPath $dir) {
            Remove-WinWSIntermediatesCacheTree -Path $dir
        }
        $ttfDir = Get-WinWSCascadiaNerdFontCachePayloadDir -CacheRootDir $dir
        $null = New-Item -ItemType Directory -Path $ttfDir -Force -ErrorAction Stop
        Get-ChildItem -LiteralPath $FontDir -Filter '*NF*.ttf' -File -ErrorAction Stop |
            Copy-Item -Destination $ttfDir -Force
        $marker = [ordered]@{
            Schema      = 4
            Kind        = 'cascadia-nerdfont'
            SavedUtc    = [datetime]::UtcNow.ToString('o')
            TagName     = $TagName
            AssetName   = $AssetName
            SourceUrl   = $SourceUrl
            Version     = $TagName
            Sha256      = $Sha256
            SizeBytes   = $SizeBytes
        }
        $marker | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $dir 'marker.json') -Encoding UTF8
    }
    catch {
        LogVerbose "cascadia-nerdfont cache publish skipped: $($_.Exception.Message)"
        if (Test-Path -LiteralPath $dir) { Remove-WinWSIntermediatesCacheTree -Path $dir }
    }
}
