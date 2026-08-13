#requires -Version 7.6
param(
    [Parameter(Mandatory)] [string] $MountDir,
    [Parameter(Mandatory)] [string] $WorkDirectory,
    [Parameter(Mandatory)] [string] $MediaDir,
    [Parameter(Mandatory)] [string] $DeviceId,
    [Parameter(Mandatory)] [string] $DetailsUrl,
    [Parameter(Mandatory)] [string] $ExpectedFileNameRegex
)
# Surface Catalog offline driver injection — param-only (issue 63).
# Download → MSI extract → SurfaceMsiSafe classify → DISM Add-Driver (install.wim + boot.wim subset).

function Test-MicrosoftDownloadUri {
    param([string] $Uri)
    $parsed = $null
    if (-not [System.Uri]::TryCreate($Uri, [System.UriKind]::Absolute, [ref]$parsed)) { return $false }
    if ($parsed.Scheme -ne 'https') { return $false }
    $parsed.Host -in @('download.microsoft.com', 'www.microsoft.com')
}

if ($MyInvocation.InvocationName -ne '.') {
$logDir = Join-Path $workDirectory 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

. (Join-Path $PSScriptRoot 'Save-WinMintDigestMap.ps1')

function Resolve-SurfaceMsiDownload {
    param([string] $Url, [string] $Pattern)
    if (-not (Test-MicrosoftDownloadUri -Uri $Url)) {
        throw "Surface driver details URL is not Microsoft-owned: $Url"
    }
    $content = (Invoke-WebRequest -Uri $Url -UseBasicParsing).Content
    $downloadUrls = @(
        [regex]::Matches($content, 'https://download\.microsoft\.com/[^"'']+?\.msi') |
            ForEach-Object { $_.Value } |
            Select-Object -Unique
    )
    if ($downloadUrls.Count -lt 1) {
        throw "No direct Microsoft MSI download URL was found on: $Url"
    }
    foreach ($u in $downloadUrls) {
        if (-not (Test-MicrosoftDownloadUri -Uri $u)) {
            throw "Surface driver page exposed a non-Microsoft MSI URL: $u"
        }
    }
    $firstUrl = [string]($downloadUrls | Select-Object -First 1)
    $fileName = [IO.Path]::GetFileName(([Uri]$firstUrl).AbsolutePath)
    if ($fileName -notmatch $Pattern) {
        throw "Surface catalog entry '$deviceId' resolved unexpected MSI '$fileName'. Expected pattern: $Pattern"
    }
    return [pscustomobject]@{ DownloadUrl = $firstUrl; FileName = $fileName }
}

function Invoke-MsiAdministrativeExtract {
    param([string] $MsiPath, [string] $Destination)
    $null = New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop
    $msiArgs = @('/a', "`"$MsiPath`"", '/qn', "TARGETDIR=`"$Destination`"")
    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -PassThru -WindowStyle Hidden
    if ($null -eq $proc) { throw "msiexec failed to launch: $MsiPath" }
    # ponytail: 10-minute cap — hung msiexec fails closed (v1 harvest).
    if (-not $proc.WaitForExit(600 * 1000)) {
        try { $proc.Kill() } catch {
            Write-Verbose 'msiexec kill failed (ignored)'
        }
        throw "msiexec administrative install timed out after 10 minutes: $MsiPath"
    }
    if ($proc.ExitCode -ne 0) {
        throw "msiexec administrative install failed (exit $($proc.ExitCode)): $MsiPath"
    }
    $infCount = (Get-ChildItem -LiteralPath $Destination -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($infCount -lt 1) {
        throw "Administrative install produced no .inf files under $Destination"
    }
}

function Read-InfMeta {
    param([string] $InfPath)
    $fields = @{ Class = ''; Provider = ''; DriverVer = '' }
    foreach ($line in (Get-Content -LiteralPath $InfPath -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*(Class|Provider|DriverVer)\s*=\s*(.+?)\s*$') {
            $fields[$matches[1]] = $matches[2].Trim().Trim('"')
        }
    }
    return [pscustomobject]@{
        Name = [IO.Path]::GetFileName($InfPath)
        Class = ([string]$fields.Class).ToLowerInvariant()
        Provider = [string]$fields.Provider
        DriverVer = [string]$fields.DriverVer
    }
}

function Test-SurfaceOfflineDriverClass {
    param([string] $Class)
    $Class -in @(
        'system', 'system ; system service', 'extension', 'net', 'hidclass',
        'keyboard', 'mouse', 'usb', 'usbdevice', 'ucm', 'battery', 'mtd',
        'monitor', 'surfacesystemmanagement'
    )
}

function Copy-ClassifiedDriverPayload {
    param([string] $DriverSource, [string] $Destination)
    $sourceRoot = (Get-Item -LiteralPath $DriverSource -ErrorAction Stop).FullName
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null = New-Item -ItemType Directory -Path $Destination -Force
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($inf in Get-ChildItem -LiteralPath $sourceRoot -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue) {
        $meta = Read-InfMeta -InfPath $inf.FullName
        $relativePath = $inf.FullName.Substring($sourceRoot.Length).TrimStart([char[]]@('\', '/'))
        $class = [string]$meta.Class
        $include = $false
        $reason = ''
        if ([string]::IsNullOrWhiteSpace($class)) {
            $reason = 'missing INF Class'
        }
        elseif ($class -eq 'firmware') {
            $reason = 'firmware drivers are never injected offline'
        }
        elseif (Test-SurfaceOfflineDriverClass -Class $class) {
            $include = $true
            $reason = 'included in offline driver subset'
        }
        else {
            $reason = "class '$class' deferred to online PnP/Windows Update"
        }
        if ($include) {
            $relDir = $inf.DirectoryName.Substring($sourceRoot.Length).TrimStart([char[]]@('\', '/'))
            $targetDir = if ([string]::IsNullOrWhiteSpace($relDir)) { $Destination } else { Join-Path $Destination $relDir }
            $null = New-Item -ItemType Directory -Path $targetDir -Force
            Get-ChildItem -LiteralPath $inf.DirectoryName -Force -ErrorAction SilentlyContinue |
                Copy-Item -Destination $targetDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        $records.Add([ordered]@{
            name = [string]$meta.Name
            relativePath = $relativePath
            class = $class
            provider = [string]$meta.Provider
            driverVer = [string]$meta.DriverVer
            decision = if ($include) { 'includeOffline' } else { 'excludeOrDefer' }
            reason = $reason
        }) | Out-Null
    }
    $included = @($records | Where-Object { $_.decision -eq 'includeOffline' })
    $excluded = @($records | Where-Object { $_.decision -ne 'includeOffline' })
    return [pscustomobject]@{
        strategy = 'SurfaceMsiSafe'
        totalInfCount = @($records).Count
        includedOfflineCount = @($included).Count
        excludedCount = @($excluded).Count
        records = @($records)
    }
}

function Copy-SetupCriticalDriverSubset {
    param([string] $DriverSource, [string] $Destination)
    $includeClasses = @('hdc', 'scsiadapter', 'system', 'usb', 'usbdevice', 'hidclass', 'keyboard', 'mouse', 'net', 'extension')
    $excludeClasses = @('display', 'media', 'camera', 'bluetooth', 'sensor', 'softwarecomponent', 'printer', 'monitor', 'firmware')
    $sourceRoot = (Get-Item -LiteralPath $DriverSource).FullName
    $null = New-Item -ItemType Directory -Path $Destination -Force
    $copied = 0
    foreach ($inf in Get-ChildItem -LiteralPath $DriverSource -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue) {
        $class = (Read-InfMeta -InfPath $inf.FullName).Class
        if ([string]::IsNullOrWhiteSpace($class)) { continue }
        if ($excludeClasses -contains $class) { continue }
        if ($includeClasses -notcontains $class) { continue }
        $rel = $inf.DirectoryName.Substring($sourceRoot.Length).TrimStart([char[]]@('\', '/'))
        $targetDir = if ([string]::IsNullOrWhiteSpace($rel)) { $Destination } else { Join-Path $Destination $rel }
        $null = New-Item -ItemType Directory -Path $targetDir -Force
        Get-ChildItem -LiteralPath $inf.DirectoryName -Force -ErrorAction SilentlyContinue |
            Copy-Item -Destination $targetDir -Recurse -Force -ErrorAction SilentlyContinue
        $copied++
    }
    return $copied
}

function Invoke-DismAddDriver {
    param([string] $ImageMount, [string] $DriverSource)
    $out = & dism.exe /English /Image:$ImageMount /Add-Driver /Driver:$DriverSource /Recurse 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "DISM Add-Driver failed ($LASTEXITCODE):`n$out"
    }
}

# --- main ---
$asset = Resolve-SurfaceMsiDownload -Url $detailsUrl -Pattern $expectedFileNameRegex
$downloadDir = Join-Path $workDirectory 'surface_catalog_download'
$null = New-Item -ItemType Directory -Path $downloadDir -Force
$msiPath = Join-Path $downloadDir $asset.FileName
Write-Output "Downloading Surface driver MSI for $deviceId…"
Invoke-WebRequest -Uri $asset.DownloadUrl -OutFile $msiPath -UseBasicParsing
$sig = Get-AuthenticodeSignature -LiteralPath $msiPath
if ([string]$sig.Status -ne 'Valid' -or [string]$sig.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
    throw "Downloaded Surface driver package is not signed by Microsoft: $msiPath"
}

$extractDir = Join-Path $workDirectory 'surface_msi_extract'
Invoke-MsiAdministrativeExtract -MsiPath $msiPath -Destination $extractDir
$surfaceUpdate = Join-Path $extractDir 'SurfaceUpdate'
if (-not (Test-Path -LiteralPath $surfaceUpdate -PathType Container)) {
    throw "Expected SurfaceUpdate folder after MSI extraction: $surfaceUpdate"
}

$preparedDir = Join-Path $workDirectory 'surface_safe_drivers'
$inventory = Copy-ClassifiedDriverPayload -DriverSource $surfaceUpdate -Destination $preparedDir
if ([int]$inventory.includedOfflineCount -lt 1) {
    throw "SurfaceMsiSafe found no offline-safe INF drivers for $deviceId"
}

Write-Output "Injecting $($inventory.includedOfflineCount) offline-safe driver(s) into install.wim…"
Invoke-DismAddDriver -ImageMount $mountDir -DriverSource $preparedDir

$bootWim = Join-Path $mediaDir 'sources\boot.wim'
$bootInfCount = 0
if (Test-Path -LiteralPath $bootWim) {
    $bootDriverSource = Join-Path $workDirectory 'surface_boot_drivers'
    try {
        $bootInfCount = Copy-SetupCriticalDriverSubset -DriverSource $preparedDir -Destination $bootDriverSource
        if ($bootInfCount -ge 1) {
            $bootMount = Join-Path (Split-Path -Parent $mountDir) 'boot-mount'
            if (Test-Path -LiteralPath $bootMount) {
                & dism.exe /English /Unmount-Image /MountDir:$bootMount /Discard 2>$null | Out-Null
                Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
            }
            New-Item -ItemType Directory -Force -Path $bootMount | Out-Null
            $null = Set-ItemProperty -Path $bootWim -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
            $info = & dism.exe /English /Get-WimInfo /WimFile:$bootWim 2>&1 | Out-String
            $indexes = @([regex]::Matches($info, '(?m)^Index : (\d+)\s*$') | ForEach-Object { [int]$_.Groups[1].Value })
            foreach ($index in $indexes) {
                Write-Output "Injecting setup-critical drivers into boot.wim index $index…"
                & dism.exe /English /Mount-Image /ImageFile:$bootWim /Index:$index /MountDir:$bootMount
                if ($LASTEXITCODE -ne 0) { throw "Mount boot.wim:$index failed: $LASTEXITCODE" }
                try {
                    Invoke-DismAddDriver -ImageMount $bootMount -DriverSource $bootDriverSource
                }
                finally {
                    & dism.exe /English /Unmount-Image /MountDir:$bootMount /Commit
                    if ($LASTEXITCODE -ne 0) { throw "Unmount boot.wim:$index failed: $LASTEXITCODE" }
                }
            }
            Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            Write-Output 'No setup-critical drivers for boot.wim; skipping WinPE injection.'
        }
    }
    finally {
        Remove-Item -LiteralPath $bootDriverSource -Recurse -Force -ErrorAction SilentlyContinue
    }
}
else {
    Write-Output "boot.wim not found at $bootWim; skipping WinPE driver injection."
}

$inventoryPath = Join-Path $logDir 'WinMint-DriverInventory.json'
@{
    schemaVersion = 1
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    deviceId = $deviceId
    strategy = $inventory.strategy
    includedOfflineCount = $inventory.includedOfflineCount
    excludedCount = $inventory.excludedCount
    bootSetupCriticalCount = $bootInfCount
    records = $inventory.records
} | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $inventoryPath -Encoding utf8
# Fail closed: apply assert expects this file; LocalAppData workdirs are not always Defender-excluded.
if (-not (Test-Path -LiteralPath $inventoryPath)) {
    throw "WinMint-DriverInventory.json missing after write: $inventoryPath"
}
$inventorySha = (Get-FileHash -LiteralPath $inventoryPath -Algorithm SHA256).Hash.ToLowerInvariant()

Save-WinMintDigestMap -WorkDirectory $workDirectory -Digests @{
    'drivers.deviceId' = $deviceId
    'drivers.includedCount' = [string]$inventory.includedOfflineCount
    'drivers.excludedCount' = [string]$inventory.excludedCount
    'drivers.inventorySha256' = $inventorySha
    'drivers.firmwareExcluded' = [string](
        @($inventory.records | Where-Object { $_.class -eq 'firmware' -and $_.decision -ne 'includeOffline' }).Count -gt 0)
}

Write-Output "InjectSurfaceDrivers ok ($($inventory.includedOfflineCount) included, $($inventory.excludedCount) excluded/deferred)"
exit 0
}
