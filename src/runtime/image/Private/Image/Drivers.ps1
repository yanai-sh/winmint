#Requires -Version 7.6

function Invoke-DriverMsiAdministrativeInstall {
    <# <summary>msiexec /a administrative install; fails if the tree contains no .inf (DISM requirement).</summary> #>
    param(
        [Parameter(Mandatory)][string]$MsiPath,
        [Parameter(Mandatory)][string]$Destination
    )
    if (-not (Test-Path -LiteralPath $MsiPath)) { throw "Driver MSI not found: $MsiPath" }
    $null = New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop

    $oldPref = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $msiArgs = @('/a', "`"$MsiPath`"", '/qn', "TARGETDIR=`"$Destination`"")
        Log "Extracting driver MSI (this can take 1-3 minutes for Surface bundles)…"
        $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -PassThru -WindowStyle Hidden
        if ($null -eq $proc) { throw "msiexec failed to launch: $MsiPath" }
        # Cap at 10 minutes. A Surface driver MSI normally extracts in ~60-90s;
        # anything slower means msiexec is hung waiting on a network resource
        # or registry call. Kill rather than hang the build forever.
        if (-not $proc.WaitForExit(600 * 1000)) {
            try { $proc.Kill() } catch { }
            throw "msiexec administrative install timed out after 10 minutes: $MsiPath"
        }
        if ($proc.ExitCode -ne 0) {
            throw "msiexec administrative install failed (exit $($proc.ExitCode)): $MsiPath"
        }
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $oldPref
    }

    $infCount = (Get-ChildItem -LiteralPath $Destination -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($infCount -lt 1) {
        throw "Administrative install produced no .inf files under $Destination (MSI: $MsiPath)."
    }
    return [int]$infCount
}

function Expand-DriverMSI {
    param([ValidateNotNullOrEmpty()][string]$MsiPath, [ValidateNotNullOrEmpty()][string]$Destination)
    if (-not (Test-Path -LiteralPath $MsiPath)) { throw "Driver MSI not found: $MsiPath" }

    $cached = Get-WinMintDriverMsiSingleExtractCacheHit -MsiPath $MsiPath
    if ($null -ne $cached) {
        Log 'Restoring driver MSI extract from temp cache…'
        if (Test-Path -LiteralPath $Destination) {
            Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue
        }
        $null = New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop
        Invoke-RobocopyChecked -Source $cached -Dest $Destination -UserFacingMessage 'Copying cached driver MSI extract…'
        Clear-WinMintReadOnlyAttribute -Path $Destination
        return
    }

    $extract = {
        LogVerbose "MSI: $MsiPath -> $Destination"
        $c = Invoke-DriverMsiAdministrativeInstall -MsiPath $MsiPath -Destination $Destination
        LogOK "Extracted $c .inf file(s) from the MSI."
    }
    if (Get-Command Invoke-Action -ErrorAction SilentlyContinue) {
        Invoke-Action 'Extracting driver MSI for DISM' $extract
    }
    else {
        & $extract
    }
    Publish-WinMintDriverMsiSingleExtractCache -MsiPath $MsiPath -SourceDir $Destination
}

function Expand-WinMintDriverZip {
    param(
        [ValidateNotNullOrEmpty()][string]$ZipPath,
        [ValidateNotNullOrEmpty()][string]$Destination
    )
    if (-not (Test-Path -LiteralPath $ZipPath)) { throw "Driver ZIP not found: $ZipPath" }
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null = New-Item -ItemType Directory -Path $Destination -Force
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $Destination -Force
    $infCount = (Get-ChildItem -LiteralPath $Destination -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($infCount -lt 1) {
        throw "Driver ZIP contains no .inf files after extraction: $ZipPath"
    }
    LogOK "Extracted driver ZIP ($infCount .inf file(s))."
}

function Test-Win11IsoDriverPayloadDirectory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $false }
    $payload = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.inf', '.msi', '.zip' } |
        Select-Object -First 1
    return $null -ne $payload
}

function Test-Win11IsoDriverPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer) { return (Test-Win11IsoDriverPayloadDirectory -Path $item.FullName) }
    return $item.Extension -in '.inf', '.msi', '.zip'
}

function Get-WinMintSurfaceDriverCatalogPath {
    Join-Path (Get-WinMintPath -Name ConfigRoot) 'surface-drivers.json'
}

function Import-WinMintSurfaceDriverCatalog {
    $path = Get-WinMintSurfaceDriverCatalogPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Surface driver catalog is missing: $path"
    }
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Get-WinMintSurfaceDriverDeviceCatalog {
    $catalog = Import-WinMintSurfaceDriverCatalog
    @($catalog.devices | ForEach-Object {
            [pscustomobject]@{
                id = [string]$_.id
                label = [string]$_.label
                name = [string]$_.name
                family = [string]$_.family
                processor = [string]$_.processor
                architecture = [string]$_.architecture
                downloadCenterId = [string]$_.downloadCenterId
                detailsUrl = [string]$_.detailsUrl
                downloadUrl = [string]$_.detailsUrl
                expectedFileNameRegex = [string]$_.expectedFileNameRegex
                minimumWindowsBuild = [int]$_.minimumWindowsBuild
                supportedOs = @($_.supportedOs)
                lifecycleEnd = [string]$_.lifecycleEnd
                aliases = @($_.aliases)
            }
        })
}

function ConvertTo-WinMintSurfaceMatchText {
    param([AllowNull()][string]$Value)

    $text = ([string]$Value).ToLowerInvariant()
    $text = $text -replace '(?<=\d)(st|nd|rd|th)\b', ''
    $text = $text -replace '\bfirst\b', '1'
    $text = $text -replace '\bsecond\b', '2'
    $text = $text -replace '\bthird\b', '3'
    $text = $text -replace '\bfourth\b', '4'
    $text = $text -replace '\bfifth\b', '5'
    $text = $text -replace '\bsixth\b', '6'
    $text = $text -replace '\bseventh\b', '7'
    $text = $text -replace '\beighth\b', '8'
    $text = $text -replace '(surfacelaptop)(\d+)', 'surface laptop $2'
    $text = $text -replace 'surface\s*laptop(\d+)', 'surface laptop $1'
    $text = $text -replace '[^a-z0-9]+', ' '
    ($text -replace '\s+', ' ').Trim()
}

function Get-WinMintSurfaceMatchTokens {
    param([string]$Value)

    @((ConvertTo-WinMintSurfaceMatchText -Value $Value) -split '\s+' | Where-Object { $_ })
}

function Get-WinMintSurfaceTokenScore {
    param(
        [string]$Query,
        [string]$Candidate
    )

    $queryTokens = @(Get-WinMintSurfaceMatchTokens -Value $Query)
    $candidateTokens = @(Get-WinMintSurfaceMatchTokens -Value $Candidate)
    if ($queryTokens.Count -lt 1 -or $candidateTokens.Count -lt 1) { return 0 }
    $intersection = @($queryTokens | Where-Object { $_ -in $candidateTokens } | Select-Object -Unique)
    $queryCoverage = [double]$intersection.Count / [double]$queryTokens.Count
    $candidateCoverage = [double]$intersection.Count / [double]$candidateTokens.Count
    [int][math]::Round((70 * $queryCoverage) + (30 * $candidateCoverage))
}

function Get-WinMintLevenshteinDistance {
    param(
        [string]$Left,
        [string]$Right
    )

    $leftLength = $Left.Length
    $rightLength = $Right.Length
    if ($leftLength -eq 0) { return $rightLength }
    if ($rightLength -eq 0) { return $leftLength }
    $matrix = New-Object 'int[,]' ($leftLength + 1), ($rightLength + 1)
    for ($i = 0; $i -le $leftLength; $i++) { $matrix[$i, 0] = $i }
    for ($j = 0; $j -le $rightLength; $j++) { $matrix[0, $j] = $j }
    for ($i = 1; $i -le $leftLength; $i++) {
        for ($j = 1; $j -le $rightLength; $j++) {
            $leftIndex = $i - 1
            $rightIndex = $j - 1
            $cost = if ($Left[$leftIndex] -eq $Right[$rightIndex]) { 0 } else { 1 }
            $delete = $matrix[$leftIndex, $j] + 1
            $insert = $matrix[$i, $rightIndex] + 1
            $substitute = $matrix[$leftIndex, $rightIndex] + $cost
            $matrix[$i, $j] = [math]::Min([math]::Min($delete, $insert), $substitute)
        }
    }
    $matrix[$leftLength, $rightLength]
}

function Get-WinMintSurfaceStringScore {
    param(
        [string]$Query,
        [string]$Candidate
    )

    $left = ConvertTo-WinMintSurfaceMatchText -Value $Query
    $right = ConvertTo-WinMintSurfaceMatchText -Value $Candidate
    if ([string]::IsNullOrWhiteSpace($left) -or [string]::IsNullOrWhiteSpace($right)) { return 0 }
    if ($left -eq $right) {
        $score = 100
    }
    elseif ($right.Contains($left) -or $left.Contains($right)) {
        $score = 95
    }
    else {
        $tokenScore = Get-WinMintSurfaceTokenScore -Query $left -Candidate $right
        $distance = Get-WinMintLevenshteinDistance -Left $left -Right $right
        $maxLength = [math]::Max($left.Length, $right.Length)
        $editScore = if ($maxLength -gt 0) { [int][math]::Round(100 * (1 - ([double]$distance / [double]$maxLength))) } else { 0 }
        $score = [math]::Max($tokenScore, $editScore)
    }
    $queryNumbers = @([regex]::Matches($left, '\d+') | ForEach-Object { $_.Value } | Select-Object -Unique)
    $candidateNumbers = @([regex]::Matches($right, '\d+') | ForEach-Object { $_.Value } | Select-Object -Unique)
    if ($queryNumbers.Count -gt 0 -and $candidateNumbers.Count -gt 0) {
        $sharedNumbers = @($queryNumbers | Where-Object { $_ -in $candidateNumbers })
        if ($sharedNumbers.Count -lt 1) { $score = [math]::Min($score, 80) }
    }
    elseif ($queryNumbers.Count -gt 0 -and $candidateNumbers.Count -eq 0) {
        $score = [math]::Min($score, 82)
    }
    if (($left -match '\bbusiness\b') -and ($right -notmatch '\bbusiness\b')) {
        $score = [math]::Min($score, 75)
    }
    [int]$score
}

function Resolve-WinMintSurfaceDriverDevice {
    param(
        [Parameter(Mandatory)][string]$Query,
        [int]$Top = 3,
        [int]$MinimumScore = 45
    )

    $surfaceMatches = [System.Collections.Generic.List[object]]::new()
    foreach ($device in Get-WinMintSurfaceDriverDeviceCatalog) {
        $names = @([string]$device.name, [string]$device.id) + @($device.aliases)
        $bestScore = 0
        $bestAlias = ''
        foreach ($name in $names) {
            $score = Get-WinMintSurfaceStringScore -Query $Query -Candidate $name
            if ($score -gt $bestScore) {
                $bestScore = $score
                $bestAlias = [string]$name
            }
        }
        if ($bestScore -ge $MinimumScore) {
            $surfaceMatches.Add([pscustomobject]@{
                id = [string]$device.id
                name = [string]$device.name
                family = [string]$device.family
                downloadCenterId = [string]$device.downloadCenterId
                downloadUrl = [string]$device.downloadUrl
                score = [int]$bestScore
                matchedAlias = $bestAlias
            }) | Out-Null
        }
    }
    @($surfaceMatches | Sort-Object @{ Expression = { [int]$_.score }; Descending = $true }, name | Select-Object -First $Top)
}

function Get-WinMintHostDeviceIdentity {
    $computer = $null
    $product = $null
    $baseBoard = $null
    $bios = $null
    try { $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop } catch { }
    try { $product = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop } catch { }
    try { $baseBoard = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop } catch { }
    try { $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop } catch { }

    [pscustomobject]@{
        manufacturer = [string]$(if ($computer) { $computer.Manufacturer } elseif ($product) { $product.Vendor } else { '' })
        model = [string]$(if ($computer) { $computer.Model } else { '' })
        productName = [string]$(if ($product) { $product.Name } else { '' })
        productVersion = [string]$(if ($product) { $product.Version } else { '' })
        baseBoardProduct = [string]$(if ($baseBoard) { $baseBoard.Product } else { '' })
        biosVersion = [string]$(if ($bios) { $bios.SMBIOSBIOSVersion } else { '' })
    }
}

function Get-WinMintSurfaceDriverDeviceQueryFromIdentity {
    param([AllowNull()][object]$Identity)

    if ($null -eq $Identity) { return @() }
    $manufacturer = [string]$(if ($Identity.PSObject.Properties['manufacturer']) { $Identity.manufacturer } else { '' })
    $values = @(
        if ($Identity.PSObject.Properties['model']) { [string]$Identity.model }
        if ($Identity.PSObject.Properties['productName']) { [string]$Identity.productName }
        if ($Identity.PSObject.Properties['baseBoardProduct']) { [string]$Identity.baseBoardProduct }
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    if ($manufacturer -notmatch '(?i)microsoft') { return @() }
    @($values | Where-Object { $_ -match '(?i)surface' })
}

function Resolve-WinMintSurfaceDriverDeviceForInput {
    param(
        [string]$MsiName = '',
        [ValidateSet('ThisPC', 'DifferentPC')][string]$TargetDevice = 'DifferentPC',
        [AllowNull()][object]$HostIdentity = $null
    )

    $queries = [System.Collections.Generic.List[object]]::new()
    if ($TargetDevice -eq 'ThisPC') {
        if ($null -eq $HostIdentity) { $HostIdentity = Get-WinMintHostDeviceIdentity }
        foreach ($query in Get-WinMintSurfaceDriverDeviceQueryFromIdentity -Identity $HostIdentity) {
            $queries.Add([pscustomobject]@{ Query = [string]$query; Source = 'host-system-info' }) | Out-Null
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($MsiName)) {
        $queries.Add([pscustomobject]@{ Query = $MsiName; Source = 'driver-msi-name' }) | Out-Null
    }

    foreach ($query in $queries) {
        $match = Resolve-WinMintSurfaceDriverDevice -Query ([string]$query.Query) -Top 1 -MinimumScore 45 | Select-Object -First 1
        if ($null -eq $match) { continue }
        $match | Add-Member -NotePropertyName matchSource -NotePropertyValue ([string]$query.Source) -Force
        $match | Add-Member -NotePropertyName matchQuery -NotePropertyValue ([string]$query.Query) -Force
        return $match
    }
    $null
}

function Resolve-WinMintSurfaceCatalogDevice {
    param([Parameter(Mandatory)][string]$DeviceId)

    $device = Get-WinMintSurfaceDriverDeviceCatalog |
        Where-Object { [string]$_.id -eq $DeviceId } |
        Select-Object -First 1
    if ($null -eq $device) {
        throw "Unknown Surface driver catalog device id '$DeviceId'."
    }
    $device
}

function Test-WinMintMicrosoftDownloadUri {
    param([Parameter(Mandatory)][string]$Uri)

    $parsed = $null
    if (-not [System.Uri]::TryCreate($Uri, [System.UriKind]::Absolute, [ref]$parsed)) { return $false }
    if ($parsed.Scheme -ne 'https') { return $false }
    $parsed.Host -in @('download.microsoft.com', 'www.microsoft.com')
}

function Assert-WinMintSurfaceCatalogDeviceCompatible {
    param(
        [Parameter(Mandatory)][object]$Device,
        [AllowEmptyString()][string]$TargetArchitecture = '',
        [int]$WindowsBuild = 0
    )

    if (-not (Test-WinMintMicrosoftDownloadUri -Uri ([string]$Device.detailsUrl))) {
        throw "Surface catalog entry '$($Device.id)' must use a Microsoft details URL."
    }
    if (-not [string]::IsNullOrWhiteSpace($TargetArchitecture)) {
        $expectedArch = [string]$Device.architecture
        if ($expectedArch -eq 'amd64') { $expectedArch = 'amd64' }
        if ($TargetArchitecture -ne $expectedArch) {
            throw "Surface driver catalog entry '$($Device.id)' targets $($Device.architecture), but the image architecture is $TargetArchitecture."
        }
    }
    if ($WindowsBuild -gt 0 -and [int]$Device.minimumWindowsBuild -gt $WindowsBuild) {
        throw "Surface driver catalog entry '$($Device.id)' requires Windows build $($Device.minimumWindowsBuild) or later; source build is $WindowsBuild."
    }
}

function Get-WinMintSurfaceDriverDownloadPageMetadata {
    param(
        [Parameter(Mandatory)][string]$DetailsUrl,
        [AllowEmptyString()][string]$Content = ''
    )

    if (-not (Test-WinMintMicrosoftDownloadUri -Uri $DetailsUrl)) {
        throw "Surface driver details URL is not Microsoft-owned: $DetailsUrl"
    }
    if ([string]::IsNullOrWhiteSpace($Content)) {
        $Content = (Invoke-WebRequest -Uri $DetailsUrl -UseBasicParsing).Content
    }
    $downloadUrls = @(
        [regex]::Matches($Content, 'https://download\.microsoft\.com/[^"'']+?\.msi') |
            ForEach-Object { $_.Value } |
            Select-Object -Unique
    )
    if ($downloadUrls.Count -lt 1) {
        throw "No direct Microsoft MSI download URL was found on: $DetailsUrl"
    }
    foreach ($url in $downloadUrls) {
        if (-not (Test-WinMintMicrosoftDownloadUri -Uri $url)) {
            throw "Surface driver page exposed a non-Microsoft MSI URL: $url"
        }
    }
    $firstUrl = [string]($downloadUrls | Select-Object -First 1)
    $fileName = [IO.Path]::GetFileName(([Uri]$firstUrl).AbsolutePath)
    $datePublished = ''
    $dateMatch = [regex]::Match($Content, '(?s)Date Published:\s*</h3>\s*<p[^>]*>\s*([^<]+)')
    if ($dateMatch.Success) {
        $datePublished = $dateMatch.Groups[1].Value.Trim()
    }
    [pscustomobject]@{
        detailsUrl = $DetailsUrl
        downloadUrl = $firstUrl
        fileName = $fileName
        datePublished = $datePublished
        allDownloadUrls = @($downloadUrls)
    }
}

function Resolve-WinMintSurfaceDriverDownloadAsset {
    param(
        [Parameter(Mandatory)][object]$Device,
        [AllowEmptyString()][string]$PageContent = ''
    )

    $metadata = Get-WinMintSurfaceDriverDownloadPageMetadata -DetailsUrl ([string]$Device.detailsUrl) -Content $PageContent
    if (-not ([string]$metadata.fileName -match [string]$Device.expectedFileNameRegex)) {
        throw "Surface catalog entry '$($Device.id)' resolved unexpected MSI '$($metadata.fileName)'. Expected pattern: $($Device.expectedFileNameRegex)"
    }
    $metadata | Add-Member -NotePropertyName deviceId -NotePropertyValue ([string]$Device.id) -Force
    $metadata | Add-Member -NotePropertyName expectedFileNameRegex -NotePropertyValue ([string]$Device.expectedFileNameRegex) -Force
    $metadata
}

function Test-WinMintSurfaceDriverPackageSignature {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ([string]$signature.Status -ne 'Valid') { return $false }
    $subject = [string]$signature.SignerCertificate.Subject
    $issuer = [string]$signature.SignerCertificate.Issuer
    ($subject -match 'Microsoft Corporation') -and ($issuer -match 'Microsoft')
}

function Save-WinMintSurfaceDriverPackage {
    param(
        [Parameter(Mandatory)][object]$Device,
        [Parameter(Mandatory)][string]$DestinationDirectory
    )

    Assert-WinMintSurfaceCatalogDeviceCompatible -Device $Device
    $asset = Resolve-WinMintSurfaceDriverDownloadAsset -Device $Device
    $null = New-Item -ItemType Directory -Path $DestinationDirectory -Force -ErrorAction Stop
    $destination = Join-Path $DestinationDirectory ([string]$asset.fileName)
    Log "Downloading Surface driver package for $($Device.name)…"
    Invoke-WebRequest -Uri ([string]$asset.downloadUrl) -OutFile $destination -UseBasicParsing
    if (-not (Test-WinMintSurfaceDriverPackageSignature -Path $destination)) {
        throw "Downloaded Surface driver package is not signed by Microsoft: $destination"
    }
    $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    [pscustomobject]@{
        path = $destination
        sha256 = $hash
        fileName = [string]$asset.fileName
        downloadUrl = [string]$asset.downloadUrl
        detailsUrl = [string]$Device.detailsUrl
        device = $Device
    }
}

function Get-WinMintInfMetadata {
    param([Parameter(Mandatory)][string]$InfPath)

    $fields = @{
        Class = ''
        Provider = ''
        DriverVer = ''
        CatalogFile = ''
    }
    foreach ($line in (Get-Content -LiteralPath $InfPath -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*(Class|Provider|DriverVer|CatalogFile(?:\.[A-Za-z0-9]+)?)\s*=\s*(.+?)\s*$') {
            $name = $matches[1]
            $value = $matches[2].Trim().Trim('"')
            if ($name -like 'CatalogFile*') { $fields.CatalogFile = $value }
            else { $fields[$name] = $value }
        }
    }

    [pscustomobject]@{
        Name = [IO.Path]::GetFileName($InfPath)
        FullName = $InfPath
        Class = ([string]$fields.Class).Trim().Trim('"').ToLowerInvariant()
        Provider = ([string]$fields.Provider).Trim().Trim('"')
        DriverVer = ([string]$fields.DriverVer).Trim().Trim('"')
        CatalogFile = ([string]$fields.CatalogFile).Trim().Trim('"')
        HasCatalog = -not [string]::IsNullOrWhiteSpace([string]$fields.CatalogFile)
    }
}

function Test-WinMintSurfaceOfflineDriverClass {
    param([string]$Class)

    $Class -in @(
        'system',
        'system ; system service',
        'extension',
        'net',
        'hidclass',
        'keyboard',
        'mouse',
        'usb',
        'usbdevice',
        'ucm',
        'battery',
        'mtd',
        'monitor',
        'surfacesystemmanagement'
    )
}

function Copy-WinMintClassifiedDriverPayload {
    param(
        [Parameter(Mandatory)][string]$DriverSource,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Strategy
    )

    $sourceRoot = (Get-Item -LiteralPath $DriverSource -ErrorAction Stop).FullName
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null = New-Item -ItemType Directory -Path $Destination -Force

    $records = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    foreach ($inf in Get-ChildItem -LiteralPath $sourceRoot -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue) {
        $meta = Get-WinMintInfMetadata -InfPath $inf.FullName
        $relativePath = $inf.FullName.Substring($sourceRoot.Length).TrimStart([char[]]@('\', '/'))
        $class = [string]$meta.Class
        $include = $false
        $reason = ''

        if ([string]::IsNullOrWhiteSpace($class)) {
            $reason = 'missing INF Class'
        }
        elseif ($class -eq 'firmware') {
            $reason = 'firmware drivers are never injected offline by default'
        }
        elseif ($Strategy -eq 'SurfaceMsiSafe') {
            $include = Test-WinMintSurfaceOfflineDriverClass -Class $class
            if (-not $include) {
                $reason = "class '$class' is deferred to online PnP/Windows Update"
            }
        }
        else {
            $include = $true
        }

        if ($include) {
            $relDir = $inf.DirectoryName.Substring($sourceRoot.Length).TrimStart([char[]]@('\', '/'))
            $targetDir = if ([string]::IsNullOrWhiteSpace($relDir)) { $Destination } else { Join-Path $Destination $relDir }
            $null = New-Item -ItemType Directory -Path $targetDir -Force
            Get-ChildItem -LiteralPath $inf.DirectoryName -Force -ErrorAction SilentlyContinue |
                Copy-Item -Destination $targetDir -Recurse -Force -ErrorAction SilentlyContinue
            $reason = 'included in offline driver subset'
        }

        if (-not $meta.HasCatalog) {
            $warnings.Add("INF has no CatalogFile metadata: $relativePath") | Out-Null
        }
        $records.Add([ordered]@{
            name = [string]$meta.Name
            relativePath = $relativePath
            class = $class
            provider = [string]$meta.Provider
            driverVer = [string]$meta.DriverVer
            catalogFile = [string]$meta.CatalogFile
            hasCatalog = [bool]$meta.HasCatalog
            decision = if ($include) { 'includeOffline' } else { 'excludeOrDefer' }
            reason = $reason
        }) | Out-Null
    }

    $included = @($records | Where-Object { $_.decision -eq 'includeOffline' })
    $excluded = @($records | Where-Object { $_.decision -ne 'includeOffline' })
    [pscustomobject]@{
        strategy = $Strategy
        sourcePath = $sourceRoot
        preparedPath = $Destination
        totalInfCount = @($records).Count
        includedOfflineCount = @($included).Count
        excludedCount = @($excluded).Count
        includedClasses = @($included | ForEach-Object { [string]$_.class } | Where-Object { $_ } | Sort-Object -Unique)
        excludedClasses = @($excluded | ForEach-Object { [string]$_.class } | Where-Object { $_ } | Sort-Object -Unique)
        warnings = @($warnings | Sort-Object -Unique)
        records = @($records)
    }
}

function Resolve-Win11IsoCustomDriverSource {
    param(
        [string]$Path,
        [Parameter(Mandatory)][string]$WorkDir,
        [ValidateSet('Custom', 'CustomInfFolder', 'OemMsi', 'SurfaceMsiSafe', 'SurfaceCatalog')][string]$DriverSource = 'Custom',
        [ValidateSet('ThisPC', 'DifferentPC')][string]$TargetDevice = 'DifferentPC',
        [AllowEmptyString()][string]$TargetArchitecture = '',
        [int]$WindowsBuild = 0,
        [AllowNull()][object]$HostIdentity = $null,
        [switch]$DryRun
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if ($DriverSource -eq 'SurfaceCatalog') {
        $surfaceCatalogDevice = Resolve-WinMintSurfaceCatalogDevice -DeviceId $Path
        Assert-WinMintSurfaceCatalogDeviceCompatible -Device $surfaceCatalogDevice -TargetArchitecture $TargetArchitecture -WindowsBuild $WindowsBuild
        if ($DryRun) {
            return [pscustomobject]@{
                Source = $Path
                Label = "Surface catalog package ($($surfaceCatalogDevice.name); downloaded during full build)"
                Ready = $false
                Strategy = 'SurfaceCatalog'
                Inventory = $null
                DeviceMatch = $surfaceCatalogDevice
            }
        }
        $downloadDir = Join-Path $WorkDir 'surface_catalog_download'
        $package = Save-WinMintSurfaceDriverPackage -Device $surfaceCatalogDevice -DestinationDirectory $downloadDir
        $prepared = Resolve-Win11IsoCustomDriverSource `
            -Path ([string]$package.path) `
            -WorkDir $WorkDir `
            -DriverSource SurfaceMsiSafe `
            -TargetDevice $TargetDevice `
            -TargetArchitecture $TargetArchitecture `
            -WindowsBuild $WindowsBuild `
            -HostIdentity $surfaceCatalogDevice
        $prepared.Strategy = 'SurfaceCatalog'
        $prepared.DeviceMatch = $surfaceCatalogDevice
        $prepared | Add-Member -NotePropertyName SurfacePackage -NotePropertyValue $package -Force
        if ($prepared.Inventory) {
            $prepared.Inventory | Add-Member -NotePropertyName surfaceDevice -NotePropertyValue $surfaceCatalogDevice -Force
            $prepared.Inventory | Add-Member -NotePropertyName surfacePackage -NotePropertyValue $package -Force
        }
        return $prepared
    }
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($DriverSource -eq 'SurfaceMsiSafe') {
        if ($item.PSIsContainer -or $item.Extension -ine '.msi') {
            throw "SurfaceMsiSafe requires a Surface driver .msi file: $($item.FullName)"
        }
        if ($DryRun) {
            return [pscustomobject]@{ Source = $item.FullName; Label = "Surface MSI safe subset ($($item.Name); classified during full build)"; Ready = $false; Strategy = 'SurfaceMsiSafe'; Inventory = $null }
        }
        $stem = ([IO.Path]::GetFileNameWithoutExtension($item.Name) -creplace '[^\w\-\.]', '_')
        if ($stem.Length -gt 24) { $stem = $stem.Substring(0, 24) }
        $extractDir = Join-Path $WorkDir ('surface_msi_' + $stem)
        Expand-DriverMSI -MsiPath $item.FullName -Destination $extractDir
        $surfaceUpdate = Join-Path $extractDir 'SurfaceUpdate'
        if (-not (Test-Path -LiteralPath $surfaceUpdate -PathType Container)) {
            throw "SurfaceMsiSafe expected a SurfaceUpdate folder after MSI extraction: $surfaceUpdate"
        }
        $preparedDir = Join-Path $WorkDir ('surface_safe_' + $stem)
        $inventory = Copy-WinMintClassifiedDriverPayload -DriverSource $surfaceUpdate -Destination $preparedDir -Strategy 'SurfaceMsiSafe'
        $surfaceDevice = Resolve-WinMintSurfaceDriverDeviceForInput -MsiName $item.Name -TargetDevice $TargetDevice -HostIdentity $HostIdentity
        if ($null -ne $surfaceDevice) {
            $inventory | Add-Member -NotePropertyName surfaceDevice -NotePropertyValue $surfaceDevice -Force
        }
        if ([int]$inventory.includedOfflineCount -lt 1) {
            throw "SurfaceMsiSafe found no offline-safe INF drivers in: $surfaceUpdate"
        }
        $deviceSuffix = if ($null -ne $surfaceDevice) { " for $($surfaceDevice.name)" } else { '' }
        LogOK "Surface MSI safe subset prepared${deviceSuffix}: $($inventory.includedOfflineCount) included, $($inventory.excludedCount) excluded/deferred."
        return [pscustomobject]@{ Source = $preparedDir; Label = "Surface MSI safe subset ($($item.Name))"; Ready = $true; Strategy = 'SurfaceMsiSafe'; Inventory = $inventory; DeviceMatch = $surfaceDevice }
    }
    if ($DriverSource -eq 'CustomInfFolder' -and -not ($item.PSIsContainer -or $item.Extension -ieq '.inf')) {
        throw "CustomInfFolder requires a .inf file or folder containing INF drivers: $($item.FullName)"
    }
    if ($DriverSource -eq 'CustomInfFolder' -and $item.PSIsContainer) {
        $infCount = (Get-ChildItem -LiteralPath $item.FullName -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($infCount -lt 1) {
            throw "CustomInfFolder requires a folder containing .inf drivers: $($item.FullName)"
        }
    }
    if ($DriverSource -eq 'OemMsi' -and ($item.PSIsContainer -or $item.Extension -ine '.msi')) {
        throw "OemMsi requires an OEM .msi file: $($item.FullName)"
    }
    if ($item.PSIsContainer) {
        if (-not (Test-Win11IsoDriverPayloadDirectory -Path $item.FullName)) {
            throw "Custom driver folder contains no .inf or .msi files: $($item.FullName)"
        }
        $infCount = (Get-ChildItem -LiteralPath $item.FullName -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($infCount -gt 0) {
            return [pscustomobject]@{ Source = $item.FullName; Label = 'Custom drivers (folder)'; Ready = $true }
        }
        if ($DryRun) {
            return [pscustomobject]@{ Source = $item.FullName; Label = 'Custom drivers (MSI in folder; expanded during full build)'; Ready = $false }
        }
        $dest = Join-Path $WorkDir 'custom_driver_msi'
        $msis = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -Filter '*.msi' -File -ErrorAction SilentlyContinue)
        $fingerprint = Get-WinMintDriverMsiSetFingerprint -MsiFiles $msis
        $cachedBundle = Get-WinMintDriverMsiBundleCacheHit -Fingerprint $fingerprint
        if ($null -ne $cachedBundle) {
            Log 'Restoring custom driver MSI folder extracts from temp cache…'
            $null = New-Item -ItemType Directory -Path $dest -Force
            Invoke-RobocopyChecked -Source $cachedBundle -Dest $dest -UserFacingMessage 'Copying cached custom driver MSI extracts…'
            Clear-WinMintReadOnlyAttribute -Path $dest
            return [pscustomobject]@{ Source = $dest; Label = 'Custom drivers (expanded MSI)'; Ready = $true }
        }
        $null = New-Item -ItemType Directory -Path $dest -Force
        foreach ($msi in $msis) {
            $safe = [IO.Path]::GetFileNameWithoutExtension($msi.Name) -creplace '[^\w\-\.]', '_'
            $sub = Join-Path $dest $safe
            $added = Invoke-DriverMsiAdministrativeInstall -MsiPath $msi.FullName -Destination $sub
            LogOK "Expanded $($msi.Name) ($added .inf file(s))."
        }
        Publish-WinMintDriverMsiBundleCache -Fingerprint $fingerprint -SourceParentDir $dest
        return [pscustomobject]@{ Source = $dest; Label = 'Custom drivers (expanded MSI)'; Ready = $true }
    }

    switch ($item.Extension.ToLowerInvariant()) {
        '.inf' {
            return [pscustomobject]@{ Source = $item.DirectoryName; Label = "Custom INF ($($item.Name))"; Ready = $true }
        }
        '.msi' {
            if ($DryRun) {
                return [pscustomobject]@{ Source = $item.FullName; Label = "Custom MSI ($($item.Name); expanded during full build)"; Ready = $false }
            }
            # Unique destination per MSI stem so a future call with a different MSI
            # file doesn't overwrite this one's expanded tree.
            $stem = [IO.Path]::GetFileNameWithoutExtension($item.Name) -creplace '[^\w\-\.]', '_'
            $dest = Join-Path $WorkDir ('custom_driver_msi_' + $stem)
            Expand-DriverMSI -MsiPath $item.FullName -Destination $dest
            return [pscustomobject]@{ Source = $dest; Label = "Custom MSI ($($item.Name))"; Ready = $true }
        }
        '.zip' {
            if ($DryRun) {
                return [pscustomobject]@{ Source = $item.FullName; Label = "Custom driver ZIP ($($item.Name); extracted during full build)"; Ready = $false }
            }
            $stem = [IO.Path]::GetFileNameWithoutExtension($item.Name) -creplace '[^\w\-\.]', '_'
            $dest = Join-Path $WorkDir ('custom_driver_zip_' + $stem)
            Expand-WinMintDriverZip -ZipPath $item.FullName -Destination $dest
            return [pscustomobject]@{ Source = $dest; Label = "Custom ZIP ($($item.Name))"; Ready = $true }
        }
        default {
            throw "Custom driver path must be a .inf file, .msi file, .zip file, or folder: $($item.FullName)"
        }
    }
}

function Export-WinMintHostDrivers {
    param([Parameter(Mandatory)][string]$Destination)

    $null = New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop
    $exported = $false
    if (Get-Command Export-WindowsDriver -ErrorAction SilentlyContinue) {
        try {
            Export-WindowsDriver -Online -Destination $Destination -ErrorAction Stop | Out-Null
            $exported = $true
        }
        catch {
            LogWarn "Export-WindowsDriver failed; falling back to pnputil /export-driver. $($_.Exception.Message)"
        }
    }

    if (-not $exported) {
        $pnputil = (Get-Command pnputil.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
        if (-not $pnputil) {
            throw 'Host driver export was requested, but neither Export-WindowsDriver nor pnputil.exe is available.'
        }

        $oldPref = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
        try {
            $out = & $pnputil /export-driver * "$Destination" 2>&1
            $code = $LASTEXITCODE
        }
        finally {
            $PSNativeCommandUseErrorActionPreference = $oldPref
        }
        if ($code -ne 0) {
            throw "pnputil host driver export failed (exit $code).`n$($out | Out-String)"
        }
    }

    $infCount = (Get-ChildItem -LiteralPath $Destination -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($infCount -lt 1) {
        throw "Host driver export produced no .inf files under $Destination."
    }
    LogOK "Host driver export produced $infCount .inf file(s)."
    return [int]$infCount
}

function Export-WinMintFilteredHostDrivers {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [ValidateSet('setup-critical', 'full')]
        [string]$Filter = 'setup-critical'
    )

    if ($Filter -eq 'full') {
        if ((Resolve-Path -LiteralPath $Source).Path -eq (Resolve-Path -LiteralPath $Destination -ErrorAction SilentlyContinue).Path) {
            return (Get-ChildItem -LiteralPath $Destination -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
        }
        if (Test-Path -LiteralPath $Destination) {
            Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue
        }
        Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
        return (Get-ChildItem -LiteralPath $Destination -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
    }

    return (Copy-WinMintSetupCriticalDrivers -DriverSource $Source -Destination $Destination)
}

function Get-WinMintInfClassName {
    param([Parameter(Mandatory)][string]$InfPath)
    $line = Get-Content -LiteralPath $InfPath -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '^\s*Class\s*=\s*(.+?)\s*$' } |
        Select-Object -First 1
    if ($line -match '^\s*Class\s*=\s*(.+?)\s*$') {
        return $matches[1].Trim().Trim('"').ToLowerInvariant()
    }
    return ''
}

function Get-WinMintSetupCriticalDriverClassPolicy {
    [ordered]@{
        Include = @(
            'hdc', 'scsiadapter', 'system', 'usb', 'usbdevice',
            'hidclass', 'keyboard', 'mouse', 'net', 'extension'
        )
        Exclude = @(
            'display', 'media', 'camera', 'bluetooth', 'sensor',
            'softwarecomponent', 'printer', 'monitor', 'firmware'
        )
    }
}

function Copy-WinMintSetupCriticalDrivers {
    param(
        [Parameter(Mandatory)][string]$DriverSource,
        [Parameter(Mandatory)][string]$Destination
    )

    $policy = Get-WinMintSetupCriticalDriverClassPolicy
    $includeClasses = @($policy.Include)
    $excludeClasses = @($policy.Exclude)
    $null = New-Item -ItemType Directory -Path $Destination -Force
    $copied = 0
    foreach ($inf in Get-ChildItem -LiteralPath $DriverSource -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue) {
        $class = Get-WinMintInfClassName -InfPath $inf.FullName
        if ([string]::IsNullOrWhiteSpace($class)) { continue }
        if ($excludeClasses -contains $class) { continue }
        if ($includeClasses -notcontains $class) { continue }
        $rel = $inf.DirectoryName.Substring((Get-Item -LiteralPath $DriverSource).FullName.Length).TrimStart([char[]]@('\', '/'))
        $targetDir = if ([string]::IsNullOrWhiteSpace($rel)) { $Destination } else { Join-Path $Destination $rel }
        $null = New-Item -ItemType Directory -Path $targetDir -Force
        Get-ChildItem -LiteralPath $inf.DirectoryName -Force -ErrorAction SilentlyContinue |
            Copy-Item -Destination $targetDir -Recurse -Force -ErrorAction SilentlyContinue
        $copied++
    }
    return $copied
}

function Invoke-DriverInjection {
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [ValidateNotNullOrEmpty()][string]$IsoContents,
        [ValidateNotNullOrEmpty()][string]$DriverSource,
        [string]$SourceLabel,
        [bool]$InjectWinPE = $true
    )
    Write-SectionHeader "Drivers: $SourceLabel"

    Invoke-Action 'Injecting drivers into Windows and WinPE (when boot.wim is present)' {
        LogVerbose "Driver folder: $DriverSource"
        $infCount = (Get-ChildItem -LiteralPath $DriverSource -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($infCount -lt 1) {
            LogWarn "No .inf files under the driver folder; skipping injection for this source."
            LogVerbose $DriverSource
            return
        }

        Log "Injecting $infCount driver(s) from $SourceLabel..."
        LogVerbose "Driver source $SourceLabel contains $infCount .inf file(s) under $DriverSource"
        $windowsTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-DismAddDriverToImage -ImageMountPath $MountDir -DriverSource $DriverSource
        $windowsTimer.Stop()
        LogOK "Drivers injected into Windows image in $(Format-WinMintDuration -Duration $windowsTimer.Elapsed)."

        $bootWim = Join-Path $IsoContents 'sources\boot.wim'
        if (-not $InjectWinPE) {
            LogVerbose 'WinPE driver injection already completed for this source; skipping boot.wim.'
            return
        }
        if (Test-Path $bootWim) {
            $bootDriverSource = Join-Path (Get-Win11IsoProcessTempPath) "Win11ISO_BootDrivers_$(Get-Random)"
            try {
                $bootInfCount = Copy-WinMintSetupCriticalDrivers -DriverSource $DriverSource -Destination $bootDriverSource
                if ($bootInfCount -lt 1) {
                    LogWarn 'No setup-critical drivers were detected for WinPE; skipping boot.wim driver injection for this source.'
                    return
                }
                $bootIndexes = @($script:BootWimDriverMountIndexes)
                Log "Injecting WinPE drivers (boot.wim indexes $($bootIndexes -join ', '))..."
                LogVerbose "WinPE setup-critical INF count: $bootInfCount"
                $null = Set-ItemProperty -Path $bootWim -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                foreach ($idx in $bootIndexes) {
                    $bootTimer = [System.Diagnostics.Stopwatch]::StartNew()
                    $bootMount = Join-Path (Get-Win11IsoProcessTempPath) "Win11ISO_BootMount_$(Get-Random)"
                    $null = New-Item -Path $bootMount -ItemType Directory -Force
                    try {
                        LogVerbose "Mounting boot.wim index $idx for WinPE driver injection."
                        Mount-WinMintImage -ImagePath $bootWim -Index $idx -MountDir $bootMount
                        Invoke-DismAddDriverToImage -ImageMountPath $bootMount -DriverSource $bootDriverSource
                        Save-WinMintImageMount -MountDir $bootMount
                        $bootTimer.Stop()
                        LogVerbose "boot.wim index $idx driver injection saved in $(Format-WinMintDuration -Duration $bootTimer.Elapsed)."
                    }
                    catch {
                        $bootTimer.Stop()
                        Dismount-WinMintImageMount -MountDir $bootMount
                        throw
                    }
                    finally {
                        $null = Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            finally {
                $null = Remove-Item -LiteralPath $bootDriverSource -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Save-WinMintDriverInventory {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Inventories,
        [Parameter(Mandatory)][string]$OutputDir
    )

    $items = @($Inventories | Where-Object { $null -ne $_ })
    if ($items.Count -lt 1) { return '' }
    $path = Join-Path $OutputDir 'WinMint-DriverInventory.json'
    $document = [ordered]@{
        schemaVersion = 1
        generatedAt = [DateTimeOffset]::Now.ToString('o')
        inventories = @($items)
    }
    $json = $document | ConvertTo-Json -Depth 32
    [System.IO.File]::WriteAllText($path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    return $path
}

