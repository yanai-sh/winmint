#Requires -Version 7.3

<#
.SYNOPSIS
    Temp cache of the post-stage ISO folder (sources\install.wim|esd) to speed repeat builds.
.NOTES
    - One active slot under %LOCALAPPDATA%\WinWS\cache\iso-stage (publishing replaces any prior entry).
    - Identity = full path + length + LastWriteTimeUtc (no full-file hash of multi-GB ISOs).
    - Default max age 48h; stale entries removed on maintenance and on read miss.
#>

$script:WinWSIsoStageCacheTtlHours = 48
$script:WinWSIsoStageCacheMarkerName = '.winws-iso-stage.json'

function Get-WinWSIsoStageCacheRoot {
    $root = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WinWS\cache\iso-stage'
    return $root
}

function New-WinWSIsoStageCacheRoot {
    $root = Get-WinWSIsoStageCacheRoot
    if (-not (Test-Path -LiteralPath $root)) {
        $null = New-Item -ItemType Directory -Path $root -Force -ErrorAction Stop
    }
    return $root
}

function Get-WinWSIsoStageCacheKeyHex {
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

function Get-WinWSIsoStageCacheFingerprint {
    param([Parameter(Mandatory)][string]$SourceIsoPath)
    $item = Get-Item -LiteralPath $SourceIsoPath -ErrorAction Stop
    $full = $item.FullName
    return "$full|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"
}

function Test-WinWSIsoStageCacheMarkerFresh {
    param([Parameter(Mandatory)][string]$MarkerPath)
    if (-not (Test-Path -LiteralPath $MarkerPath)) { return $false }
    try {
        $meta = Get-Content -LiteralPath $MarkerPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $saved = [datetime]::Parse([string]$meta.SavedUtc, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        $age = [datetime]::UtcNow - $saved
        return ($age.TotalHours -lt $script:WinWSIsoStageCacheTtlHours)
    }
    catch {
        return $false
    }
}

function Remove-WinWSIsoStageCacheDirectory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    }
    catch {
        LogVerbose "IsoStageCache: could not remove '$Path': $($_.Exception.Message)"
    }
}

function Invoke-WinWSIsoStageCacheMaintenance {
    <#
    .SYNOPSIS
        Drops expired cache folders (TTL) and broken markers. Safe to call from startup cleanup.
    #>
    $root = Get-WinWSIsoStageCacheRoot
    if (-not (Test-Path -LiteralPath $root)) { return }
    foreach ($child in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $marker = Join-Path $child.FullName $script:WinWSIsoStageCacheMarkerName
        if (-not (Test-Path -LiteralPath $marker)) {
            Remove-WinWSIsoStageCacheDirectory -Path $child.FullName
            continue
        }
        if (-not (Test-WinWSIsoStageCacheMarkerFresh -MarkerPath $marker)) {
            Remove-WinWSIsoStageCacheDirectory -Path $child.FullName
        }
    }
}

function Get-WinWSIsoStageCacheHit {
    param([Parameter(Mandatory)][string]$SourceIsoPath)
    Invoke-WinWSIsoStageCacheMaintenance

    if (-not (Test-Path -LiteralPath $SourceIsoPath)) { return $null }

    $fp = Get-WinWSIsoStageCacheFingerprint -SourceIsoPath $SourceIsoPath
    $key = Get-WinWSIsoStageCacheKeyHex -Fingerprint $fp
    $dir = Join-Path (Get-WinWSIsoStageCacheRoot) $key
    $marker = Join-Path $dir $script:WinWSIsoStageCacheMarkerName

    if (-not (Test-Path -LiteralPath $marker)) { return $null }
    if (-not (Test-WinWSIsoStageCacheMarkerFresh -MarkerPath $marker)) {
        Remove-WinWSIsoStageCacheDirectory -Path $dir
        return $null
    }

    try {
        $meta = Get-Content -LiteralPath $marker -Raw -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        Remove-WinWSIsoStageCacheDirectory -Path $dir
        return $null
    }

    $item = Get-Item -LiteralPath $SourceIsoPath -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    if ([string]$meta.FullPath -ne $item.FullName) { return $null }
    if ([long]$meta.Length -ne $item.Length) { return $null }
    if ([long]$meta.LastWriteUtcTicks -ne $item.LastWriteTimeUtc.Ticks) { return $null }

    # Cache is published only after ESD→WIM so DISM-serviced layout is always install.wim.
    $wim = Join-Path $dir 'sources\install.wim'
    if (-not (Test-Path -LiteralPath $wim)) { return $null }

    return $dir
}

function Publish-WinWSIsoStageCache {
    param(
        [Parameter(Mandatory)][string]$SourceIsoPath,
        [Parameter(Mandatory)][string]$IsoContentsPath
    )

    if (-not (Test-Path -LiteralPath $SourceIsoPath)) { return }
    if (-not (Test-Path -LiteralPath $IsoContentsPath)) { return }

    $wim = Join-Path $IsoContentsPath 'sources\install.wim'
    if (-not (Test-Path -LiteralPath $wim)) { return }

    $dest = $null
    try {
        $root = New-WinWSIsoStageCacheRoot
        foreach ($child in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            Remove-WinWSIsoStageCacheDirectory -Path $child.FullName
        }

        $fp = Get-WinWSIsoStageCacheFingerprint -SourceIsoPath $SourceIsoPath
        $key = Get-WinWSIsoStageCacheKeyHex -Fingerprint $fp
        $dest = Join-Path $root $key
        if (Test-Path -LiteralPath $dest) { Remove-WinWSIsoStageCacheDirectory -Path $dest }
        $null = New-Item -ItemType Directory -Path $dest -Force -ErrorAction Stop

        Invoke-RobocopyChecked -Source $IsoContentsPath -Dest $dest -UserFacingMessage 'Saving temp cache of staged ISO for faster rebuilds (~5 GB; robocopy runs silently)…'

        $item = Get-Item -LiteralPath $SourceIsoPath -ErrorAction Stop
        $marker = [ordered]@{
            FullPath          = $item.FullName
            Length            = $item.Length
            LastWriteUtcTicks = $item.LastWriteTimeUtc.Ticks
            SavedUtc          = [datetime]::UtcNow.ToString('o')
            Schema            = 1
        }
        $markerPath = Join-Path $dest $script:WinWSIsoStageCacheMarkerName
        [System.IO.File]::WriteAllText(
            $markerPath,
            ($marker | ConvertTo-Json -Compress),
            [System.Text.UTF8Encoding]::new($false))
    }
    catch {
        LogVerbose "IsoStageCache publish skipped: $($_.Exception.Message)"
        if ($null -ne $dest -and (Test-Path -LiteralPath $dest)) { Remove-WinWSIsoStageCacheDirectory -Path $dest }
    }
}
