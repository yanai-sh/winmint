#Requires -Version 7.6

function ConvertTo-WinMintPlainText {
    param([AllowNull()][string]$Html)

    if ([string]::IsNullOrWhiteSpace($Html)) { return '' }
    $text = [regex]::Replace($Html, '<script[\s\S]*?</script>', ' ')
    $text = [regex]::Replace($text, '<style[\s\S]*?</style>', ' ')
    $text = [regex]::Replace($text, '<[^>]+>', ' ')
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    $text = $text -replace [char]0x00A0, ' '
    return ([regex]::Replace($text, '\s+', ' ')).Trim()
}

function ConvertFrom-WinMintCatalogBase64Sha256 {
    param([Parameter(Mandatory)][string]$Sha256Base64)

    try {
        $bytes = [Convert]::FromBase64String($Sha256Base64)
    }
    catch {
        throw "Invalid Base64 SHA256 value from Microsoft Update Catalog: $Sha256Base64"
    }
    if ($bytes.Length -ne 32) {
        throw "Microsoft Update Catalog SHA256 value decoded to $($bytes.Length) bytes, expected 32."
    }
    return ([BitConverter]::ToString($bytes) -replace '-', '').ToUpperInvariant()
}

function ConvertTo-WinMintCatalogArchitectureLabel {
    param([Parameter(Mandatory)][string]$Architecture)

    switch ($Architecture) {
        'arm64' { return 'arm64-based' }
        'amd64' { return 'x64-based' }
        'x64' { return 'x64-based' }
        'x86' { return 'x86-based' }
        default { throw "Unsupported update payload architecture: $Architecture" }
    }
}

function ConvertTo-WinMintDefenderArchitectureLabel {
    param([Parameter(Mandatory)][string]$Architecture)

    switch ($Architecture) {
        'arm64' { return 'arm' }
        'amd64' { return 'x64' }
        'x64' { return 'x64' }
        'x86' { return 'x86' }
        default { throw "Unsupported Defender update architecture: $Architecture" }
    }
}

function Get-WinMintMicrosoftUpdateCatalogRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Query)

    $encoded = [uri]::EscapeDataString($Query)
    $uri = "https://www.catalog.update.microsoft.com/Search.aspx?q=$encoded"
    $headers = @{ 'User-Agent' = 'Mozilla/5.0 WinMint/1.0' }
    $response = Invoke-WebRequest -Verbose:$false -Uri $uri -UseBasicParsing -Headers $headers -ErrorAction Stop
    $content = [string]$response.Content
    $rowPattern = '(?is)<tr\s+id="(?<id>[0-9a-f-]{36})_R(?<row>\d+)"[^>]*>(?<html>.*?)</tr>'
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($match in [regex]::Matches($content, $rowPattern)) {
        $updateId = [string]$match.Groups['id'].Value
        $rowHtml = [string]$match.Groups['html'].Value
        $cells = @{}
        $cellPattern = "(?is)<td[^>]*id=`"$([regex]::Escape($updateId))_C(?<col>\d+)_R\d+`"[^>]*>(?<html>.*?)</td>"
        foreach ($cell in [regex]::Matches($rowHtml, $cellPattern)) {
            $cells[[int]$cell.Groups['col'].Value] = ConvertTo-WinMintPlainText ([string]$cell.Groups['html'].Value)
        }
        if (-not $cells.ContainsKey(1)) { continue }
        $lastUpdated = $null
        if ($cells.ContainsKey(4) -and -not [string]::IsNullOrWhiteSpace([string]$cells[4])) {
            [DateTime]$parsedDate = [DateTime]::MinValue
            if ([DateTime]::TryParse([string]$cells[4], [ref]$parsedDate)) {
                $lastUpdated = $parsedDate
            }
        }
        $originalSizeBytes = 0L
        $sizeMatch = [regex]::Match($rowHtml, '<span\s+class="noDisplay"[^>]*_originalSize"[^>]*>\s*(?<size>\d+)\s*</span>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($sizeMatch.Success) { $originalSizeBytes = [long]$sizeMatch.Groups['size'].Value }
        $rows.Add([pscustomobject]@{
                UpdateId = $updateId
                Title = [string]$cells[1]
                Products = if ($cells.ContainsKey(2)) { [string]$cells[2] } else { '' }
                Classification = if ($cells.ContainsKey(3)) { [string]$cells[3] } else { '' }
                LastUpdatedText = if ($cells.ContainsKey(4)) { [string]$cells[4] } else { '' }
                LastUpdated = $lastUpdated
                Version = if ($cells.ContainsKey(5)) { [string]$cells[5] } else { '' }
                Size = if ($cells.ContainsKey(6)) { [string]$cells[6] } else { '' }
                OriginalSizeBytes = $originalSizeBytes
                Query = $Query
                CatalogUrl = $uri
            }) | Out-Null
    }
    return $rows.ToArray()
}

function Test-WinMintCatalogRowForKind {
    param(
        [Parameter(Mandatory)]$Row,
        [Parameter(Mandatory)][ValidateSet('QualitySecurity', 'SetupDynamic', 'SafeOSDynamic', 'DotNet')][string]$Kind,
        [Parameter(Mandatory)][string]$ArchitectureLabel,
        [Parameter(Mandatory)][string]$TargetFeatureVersion
    )

    $title = [string]$Row.Title
    if ([string]::IsNullOrWhiteSpace($title)) { return $false }
    if ($title -match '(?i)\bPreview\b') { return $false }
    if ($title -notmatch [regex]::Escape($ArchitectureLabel)) { return $false }
    if ($title -notmatch "(?i)version\s+$([regex]::Escape($TargetFeatureVersion))") { return $false }

    switch ($Kind) {
        'QualitySecurity' {
            return (
                $title -match '(?i)^20\d\d-\d\d\s+Cumulative Update for Windows 11,' -and
                $title -notmatch '(?i)\.NET|Dynamic Update' -and
                [string]$Row.Classification -eq 'Security Updates'
            )
        }
        'SetupDynamic' {
            return (
                $title -match '(?i)Setup Dynamic Update for Windows 11' -and
                [string]$Row.Classification -eq 'Critical Updates'
            )
        }
        'SafeOSDynamic' {
            return (
                $title -match '(?i)Safe OS Dynamic Update for Windows 11' -and
                [string]$Row.Classification -eq 'Critical Updates'
            )
        }
        'DotNet' {
            return (
                $title -match '(?i)Cumulative Update for \.NET Framework' -and
                $title -match '(?i)Windows 11' -and
                [string]$Row.Classification -eq 'Security Updates'
            )
        }
    }
    return $false
}

function Select-WinMintMicrosoftUpdateCatalogRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('QualitySecurity', 'SetupDynamic', 'SafeOSDynamic', 'DotNet')][string]$Kind,
        [Parameter(Mandatory)][string]$Architecture,
        [string]$TargetFeatureVersion = '25H2'
    )

    $architectureLabel = ConvertTo-WinMintCatalogArchitectureLabel -Architecture $Architecture
    $query = switch ($Kind) {
        'QualitySecurity' { "Cumulative Update Windows 11 version $TargetFeatureVersion $architectureLabel" }
        'SetupDynamic' { "Setup Dynamic Update Windows 11 version $TargetFeatureVersion $architectureLabel" }
        'SafeOSDynamic' { "Safe OS Dynamic Update Windows 11 version $TargetFeatureVersion $architectureLabel" }
        'DotNet' { "Cumulative Update .NET Framework Windows 11 version $TargetFeatureVersion $architectureLabel" }
    }
    $rows = @(Get-WinMintMicrosoftUpdateCatalogRows -Query $query)
    $candidateRows = @(
        $rows |
            Where-Object {
                Test-WinMintCatalogRowForKind `
                    -Row $_ `
                    -Kind $Kind `
                    -ArchitectureLabel $architectureLabel `
                    -TargetFeatureVersion $TargetFeatureVersion
            } |
            Sort-Object @{ Expression = { if ($_.LastUpdated) { $_.LastUpdated } else { [DateTime]::MinValue } }; Descending = $true },
            @{ Expression = 'Title'; Descending = $true }
    )
    if ($candidateRows.Count -eq 0) {
        throw "Microsoft Update Catalog query returned no $Kind payload for Windows 11 $TargetFeatureVersion $architectureLabel. Query: $query"
    }
    return $candidateRows[0]
}

function Get-WinMintMicrosoftUpdateCatalogDownloadFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$UpdateId,
        [Parameter(Mandatory)][string]$RefererQuery
    )

    $json = '[{"size":0,"languages":"","uidInfo":"' + $UpdateId + '","updateID":"' + $UpdateId + '"}]'
    $body = 'updateIDs=' + [uri]::EscapeDataString($json)
    $headers = @{
        'User-Agent' = 'Mozilla/5.0 WinMint/1.0'
        'Referer' = "https://www.catalog.update.microsoft.com/Search.aspx?q=$([uri]::EscapeDataString($RefererQuery))"
    }
    $response = Invoke-WebRequest `
        -Verbose:$false `
        -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' `
        -Method Post `
        -Body $body `
        -ContentType 'application/x-www-form-urlencoded' `
        -UseBasicParsing `
        -Headers $headers `
        -ErrorAction Stop
    $content = [string]$response.Content
    $files = [System.Collections.Generic.List[object]]::new()
    $pattern = "(?is)downloadInformation\[\d+\]\.files\[(?<index>\d+)\]\.url\s*=\s*'(?<url>[^']+)';(?<body>.*?)(?=downloadInformation\[\d+\]\.files\[\d+\]\.url\s*=|</script>)"
    foreach ($match in [regex]::Matches($content, $pattern)) {
        $fileBody = [string]$match.Groups['body'].Value
        $url = [System.Net.WebUtility]::HtmlDecode([string]$match.Groups['url'].Value)
        $shaMatch = [regex]::Match($fileBody, "sha256\s*=\s*'(?<sha>[^']*)'", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $nameMatch = [regex]::Match($fileBody, "fileName\s*=\s*'(?<name>[^']*)'", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $shaMatch.Success -or [string]::IsNullOrWhiteSpace([string]$shaMatch.Groups['sha'].Value)) {
            throw "Microsoft Update Catalog did not provide SHA256 metadata for $url"
        }
        $fileName = if ($nameMatch.Success) {
            [System.Net.WebUtility]::HtmlDecode([string]$nameMatch.Groups['name'].Value)
        }
        else {
            [IO.Path]::GetFileName(([uri]$url).AbsolutePath)
        }
        $shaBase64 = [string]$shaMatch.Groups['sha'].Value
        $files.Add([pscustomobject]@{
                Url = $url
                FileName = $fileName
                Sha256Base64 = $shaBase64
                Sha256 = ConvertFrom-WinMintCatalogBase64Sha256 -Sha256Base64 $shaBase64
            }) | Out-Null
    }
    if ($files.Count -eq 0) {
        throw "Microsoft Update Catalog download dialog returned no downloadable files for update ID $UpdateId."
    }
    return $files.ToArray()
}

function Invoke-WinMintUpdatePayloadDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    $parent = Split-Path -Parent $DestinationPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue

    $bits = Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue
    if ($bits) {
        try {
            Start-BitsTransfer `
                -Source $Uri `
                -Destination $DestinationPath `
                -DisplayName 'WinMint update payload' `
                -Description $Uri `
                -TransferType Download `
                -Priority Foreground `
                -ErrorAction Stop
            return
        }
        catch {
            LogWarn "BITS download failed; falling back to Invoke-WebRequest. $($_.Exception.Message)"
            Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
        }
    }

    Invoke-WebRequest `
        -Verbose:$false `
        -Uri $Uri `
        -OutFile $DestinationPath `
        -Headers @{ 'User-Agent' = 'WinMint/1.0' } `
        -ErrorAction Stop
}

function Save-WinMintVerifiedDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Download,
        [Parameter(Mandatory)][string]$DestinationDirectory
    )

    $null = New-Item -ItemType Directory -Path $DestinationDirectory -Force
    $safeName = ([string]$Download.FileName -replace '[<>:"|?*\\/]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        $safeName = [IO.Path]::GetFileName(([uri][string]$Download.Url).AbsolutePath)
    }
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        $safeName = 'microsoft-update-' + [Guid]::NewGuid().ToString('n') + '.msu'
    }
    $destination = Join-Path $DestinationDirectory $safeName
    $expectedHash = [string]$Download.Sha256
    if ((Test-Path -LiteralPath $destination -PathType Leaf) -and
        ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $expectedHash)) {
        LogVerbose "Using verified Microsoft update payload: $safeName"
        return (Get-Item -LiteralPath $destination).FullName
    }

    $part = "$destination.part"
    try {
        Invoke-WinMintUpdatePayloadDownload -Uri ([string]$Download.Url) -DestinationPath $part
        $actualHash = (Get-FileHash -LiteralPath $part -Algorithm SHA256).Hash
        if ($actualHash -ne $expectedHash) {
            throw "SHA256 mismatch for $safeName. Expected $expectedHash, got $actualHash."
        }
        Move-Item -LiteralPath $part -Destination $destination -Force
    }
    catch {
        Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
        throw
    }
    return (Get-Item -LiteralPath $destination).FullName
}

function Assert-WinMintMicrosoftSignature {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    if ($signature.Status -ne 'Valid') {
        throw "Microsoft payload signature validation failed for $Path. Status: $($signature.Status)."
    }
    $subject = [string]$signature.SignerCertificate.Subject
    if ($subject -notmatch '(?i)Microsoft') {
        throw "Payload signature for $Path is valid, but signer is not Microsoft: $subject"
    }
}

function Save-WinMintDefenderOfflineImageUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PayloadRoot,
        [Parameter(Mandatory)][string]$Architecture
    )

    $defenderArch = ConvertTo-WinMintDefenderArchitectureLabel -Architecture $Architecture
    $url = "https://definitionupdates.microsoft.com/packages?package=dismpackage&arch=$defenderArch"
    $categoryDir = Join-Path $PayloadRoot 'defender'
    $kitDir = Join-Path $categoryDir "offline-kit-$defenderArch"
    $zipPath = Join-Path $categoryDir "defender-update-kit-$defenderArch.zip"
    $null = New-Item -ItemType Directory -Path $categoryDir -Force
    $existingCab = Get-ChildItem -LiteralPath $kitDir -Filter 'defender-dism-*.cab' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($existingCab) {
        Assert-WinMintMicrosoftSignature -Path $existingCab.FullName
        return @([pscustomobject]@{
                category = 'defender'
                source = 'Microsoft Defender offline image update'
                url = $url
                fileName = $existingCab.Name
                path = $existingCab.FullName
                sha256 = (Get-FileHash -LiteralPath $existingCab.FullName -Algorithm SHA256).Hash
                sizeBytes = [long]$existingCab.Length
            })
    }

    $part = "$zipPath.part"
    try {
        Invoke-WinMintUpdatePayloadDownload -Uri $url -DestinationPath $part
        Move-Item -LiteralPath $part -Destination $zipPath -Force
        if (Test-Path -LiteralPath $kitDir) {
            Remove-Item -LiteralPath $kitDir -Recurse -Force -ErrorAction Stop
        }
        $null = New-Item -ItemType Directory -Path $kitDir -Force
        Expand-Archive -LiteralPath $zipPath -DestinationPath $kitDir -Force
    }
    catch {
        Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
        throw
    }

    $cab = Get-ChildItem -LiteralPath $kitDir -Filter 'defender-dism-*.cab' -Recurse -File -ErrorAction Stop |
        Select-Object -First 1
    if (-not $cab) {
        throw "Defender offline image update kit did not contain defender-dism-*.cab: $zipPath"
    }
    Assert-WinMintMicrosoftSignature -Path $cab.FullName
    $tool = Get-ChildItem -LiteralPath $kitDir -Filter 'DefenderUpdateWinImage.ps1' -Recurse -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($tool) {
        Assert-WinMintMicrosoftSignature -Path $tool.FullName
    }
    return @([pscustomobject]@{
            category = 'defender'
            source = 'Microsoft Defender offline image update'
            url = $url
            fileName = $cab.Name
            path = $cab.FullName
            sha256 = (Get-FileHash -LiteralPath $cab.FullName -Algorithm SHA256).Hash
            sizeBytes = [long]$cab.Length
            kitSha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
            kitPath = $zipPath
        })
}

function Save-WinMintUpdatePayloadManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PayloadRoot,
        [Parameter(Mandatory)][string]$Architecture,
        [Parameter(Mandatory)]$Updates,
        [Parameter(Mandatory)][object[]]$Payloads
    )

    $manifest = [ordered]@{
        schemaVersion = 1
        generatedAt = [DateTimeOffset]::Now.ToString('o')
        sourcePolicy = 'Official Microsoft sources only: Microsoft Update Catalog and Microsoft Defender offline image update endpoint.'
        architecture = $Architecture
        mode = [string]$Updates.Mode
        targetFeatureVersion = [string]$Updates.TargetFeatureVersion
        releaseCadence = [string]$Updates.ReleaseCadence
        includeOptionalPreviews = [bool]$Updates.IncludeOptionalPreviews
        payloads = @($Payloads)
    }
    $path = Join-Path $PayloadRoot 'UpdatePayloadManifest.json'
    $json = $manifest | ConvertTo-Json -Depth 12
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($path, $json + [Environment]::NewLine, $utf8NoBom)
    return $path
}

function Invoke-WinMintStable25H2UpdatePayloadAcquisition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Updates,
        [Parameter(Mandatory)][string]$Architecture
    )

    if ($null -eq $Updates -or [string]$Updates.Mode -eq 'None') { return $null }
    if ([string]$Updates.Mode -ne 'Stable25H2') {
        throw "Unsupported image update mode: $($Updates.Mode)"
    }
    if ([bool]$Updates.IncludeOptionalPreviews) {
        throw 'Optional preview update acquisition is not allowed for Stable25H2.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Updates.PayloadRoot)) {
        throw 'Stable25H2 update acquisition requires updates.payloadRoot.'
    }
    if ([string]::IsNullOrWhiteSpace($Architecture)) {
        throw 'Stable25H2 update acquisition requires a target architecture.'
    }

    $payloadRoot = [string]$Updates.PayloadRoot
    $null = New-Item -ItemType Directory -Path $payloadRoot -Force
    $payloads = [System.Collections.Generic.List[object]]::new()
    $catalogPlan = @(
        [pscustomobject]@{ Kind = 'QualitySecurity'; Category = 'packages'; Enabled = [bool]$Updates.QualitySecurity }
        [pscustomobject]@{ Kind = 'SetupDynamic'; Category = 'dynamic-update'; Enabled = [bool]$Updates.DynamicUpdate }
        [pscustomobject]@{ Kind = 'SafeOSDynamic'; Category = 'dynamic-update'; Enabled = [bool]$Updates.DynamicUpdate }
        [pscustomobject]@{ Kind = 'DotNet'; Category = 'dotnet'; Enabled = [bool]$Updates.DotNet }
    )

    foreach ($entry in $catalogPlan) {
        if (-not [bool]$entry.Enabled) { continue }
        $row = $null
        try {
            $row = Select-WinMintMicrosoftUpdateCatalogRow `
                -Kind ([string]$entry.Kind) `
                -Architecture $Architecture `
                -TargetFeatureVersion ([string]$Updates.TargetFeatureVersion)
        }
        catch {
            if ([string]$entry.Kind -eq 'DotNet') {
                LogWarn "No matching .NET Microsoft Update Catalog payload was found; continuing without .NET offline update. $($_.Exception.Message)"
                continue
            }
            throw
        }
        Log "Resolved Microsoft Update Catalog payload: $($row.Title)"
        $downloads = @(Get-WinMintMicrosoftUpdateCatalogDownloadFile -UpdateId ([string]$row.UpdateId) -RefererQuery ([string]$row.Query))
        $destinationDir = Join-Path $payloadRoot ([string]$entry.Category)
        foreach ($download in $downloads) {
            $path = Save-WinMintVerifiedDownload -Download $download -DestinationDirectory $destinationDir
            $item = Get-Item -LiteralPath $path -ErrorAction Stop
            $payloads.Add([ordered]@{
                    category = [string]$entry.Category
                    kind = [string]$entry.Kind
                    title = [string]$row.Title
                    updateId = [string]$row.UpdateId
                    lastUpdated = [string]$row.LastUpdatedText
                    catalogUrl = [string]$row.CatalogUrl
                    url = [string]$download.Url
                    fileName = $item.Name
                    path = $item.FullName
                    sha256 = [string]$download.Sha256
                    sha256Base64 = [string]$download.Sha256Base64
                    sizeBytes = [long]$item.Length
                }) | Out-Null
        }
    }

    if ([bool]$Updates.Defender) {
        foreach ($payload in @(Save-WinMintDefenderOfflineImageUpdate -PayloadRoot $payloadRoot -Architecture $Architecture)) {
            $payloads.Add($payload) | Out-Null
        }
    }

    $manifestPath = Save-WinMintUpdatePayloadManifest `
        -PayloadRoot $payloadRoot `
        -Architecture $Architecture `
        -Updates $Updates `
        -Payloads $payloads.ToArray()
    LogOK "Update payload acquisition complete: $manifestPath"
    return [pscustomobject]@{
        PayloadRoot = $payloadRoot
        ManifestPath = $manifestPath
        PayloadCount = $payloads.Count
        Payloads = $payloads.ToArray()
    }
}

