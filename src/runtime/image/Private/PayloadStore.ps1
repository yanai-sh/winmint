#Requires -Version 7.3

function New-WinMintPayloadResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$SourceUrl,
        [Parameter(Mandatory)][string]$Version,
        [string]$AssetName = '',
        [ValidateSet('release', 'cache', 'local')][string]$SourceStatus = 'local',
        [ValidateSet('keep', 'delete-if-outside-cache')][string]$CleanupPolicy = 'delete-if-outside-cache',
        [string]$HashLabel = ''
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Payload '$Name' was resolved to a missing file: $Path"
    }

    if ([string]::IsNullOrWhiteSpace($AssetName)) {
        $AssetName = [IO.Path]::GetFileName($Path)
    }
    if ([string]::IsNullOrWhiteSpace($HashLabel)) {
        $HashLabel = "$Name ($AssetName)"
    }

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    [pscustomobject]@{
        Name = $Name
        Path = $item.FullName
        SourceUrl = $SourceUrl
        Version = $Version
        Sha256 = Assert-Win11IsoFileHash -FilePath $item.FullName -Label $HashLabel
        SizeBytes = [long]$item.Length
        AssetName = $AssetName
        SourceStatus = $SourceStatus
        CleanupPolicy = $CleanupPolicy
    }
}

function Add-WinMintManifestPayloadFact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Payload
    )

    Add-WinMintManifestPayload `
        -Name ([string]$Payload.Name) `
        -SourceUrl ([string]$Payload.SourceUrl) `
        -Version ([string]$Payload.Version) `
        -Sha256 ([string]$Payload.Sha256) `
        -SizeBytes ([long]$Payload.SizeBytes)
}

function Remove-WinMintPayloadResult {
    [CmdletBinding()]
    param(
        [AllowNull()]$Payload
    )

    if ($null -eq $Payload) { return }
    $path = [string]$Payload.Path
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return
    }
    if ([string]$Payload.CleanupPolicy -ne 'delete-if-outside-cache') {
        return
    }
    if (-not (Test-IsPathUnderWin11IsoDependencyCache $path)) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-WinMintCachedPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Patterns,
        [string]$VersionRegex = '',
        [string]$HashLabel = ''
    )

    $path = Get-WinMintCachedDownloadFile -Patterns $Patterns
    if (-not $path) {
        throw "$Name cache missing $($Patterns -join ', ')."
    }

    $assetName = [IO.Path]::GetFileName($path)
    $version = 'cached'
    if (-not [string]::IsNullOrWhiteSpace($VersionRegex) -and $assetName -match $VersionRegex) {
        $version = if ($Matches['Version']) { [string]$Matches['Version'] } else { [string]$Matches[1] }
        if ($version -match '^\d') { $version = "v$version" }
    }

    New-WinMintPayloadResult `
        -Name $Name `
        -Path $path `
        -SourceUrl "cache:$assetName" `
        -Version $version `
        -AssetName $assetName `
        -SourceStatus cache `
        -CleanupPolicy keep `
        -HashLabel $HashLabel
}

function Select-WinMintGitHubReleaseAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Release,
        [Parameter(Mandatory)][scriptblock]$AssetSelector
    )

    $asset = $null
    $bestScore = 0
    foreach ($candidate in @($Release.assets)) {
        $selected = & $AssetSelector $candidate $Release
        $score = 0
        if ($selected -is [int] -or $selected -is [long]) {
            $score = [int]$selected
        }
        elseif ([bool]$selected) {
            $score = 1
        }
        if ($score -gt $bestScore) {
            $asset = $candidate
            $bestScore = $score
        }
    }
    if (-not $asset) {
        $available = (@($Release.assets) | ForEach-Object { $_.name }) -join ', '
        throw "$Name release $($Release.tag_name) has no matching asset. Available: $available"
    }
    return $asset
}

function Get-WinMintPayloadSpecValue {
    param(
        [Parameter(Mandatory)]$Spec,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($Spec -is [System.Collections.IDictionary] -and $Spec.Contains($Name)) {
        return $Spec[$Name]
    }
    if ($Spec.PSObject.Properties[$Name]) {
        return $Spec.$Name
    }
    return $Default
}

function Resolve-WinMintGitHubReleasePayloadSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoSlug,
        [Parameter(Mandatory)][object[]]$PayloadSpecs,
        [hashtable]$Headers = @{ 'User-Agent' = 'WinMint/1.0' }
    )

    $releaseError = $null
    try {
        $release = Invoke-RestMethod -Verbose:$false -Uri "https://api.github.com/repos/$RepoSlug/releases/latest" -Headers $Headers
        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($spec in @($PayloadSpecs)) {
            $name = [string](Get-WinMintPayloadSpecValue -Spec $spec -Name 'Name')
            $selector = Get-WinMintPayloadSpecValue -Spec $spec -Name 'AssetSelector'
            $hashLabel = [string](Get-WinMintPayloadSpecValue -Spec $spec -Name 'HashLabel' -Default $name)
            if ([string]::IsNullOrWhiteSpace($name) -or -not ($selector -is [scriptblock])) {
                throw "Invalid payload spec for $RepoSlug; Name and AssetSelector are required."
            }

            $asset = Select-WinMintGitHubReleaseAsset -Name $name -Release $release -AssetSelector $selector
            $path = Invoke-WebRequestCachedFile -Uri $asset.browser_download_url -CacheFileName $asset.name -Headers $Headers
            $results.Add((New-WinMintPayloadResult `
                        -Name $name `
                        -Path $path `
                        -SourceUrl ([string]$asset.browser_download_url) `
                        -Version ([string]$release.tag_name) `
                        -AssetName ([string]$asset.name) `
                        -SourceStatus release `
                        -CleanupPolicy keep `
                        -HashLabel $hashLabel)) | Out-Null
        }
        return $results.ToArray()
    }
    catch {
        $releaseError = $_
        if (Get-Command LogWarn -ErrorAction SilentlyContinue) {
            LogWarn "$RepoSlug release lookup failed; trying cached payloads. $($releaseError.Exception.Message)"
        }
    }

    try {
        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($spec in @($PayloadSpecs)) {
            $name = [string](Get-WinMintPayloadSpecValue -Spec $spec -Name 'Name')
            $patterns = [string[]]@(Get-WinMintPayloadSpecValue -Spec $spec -Name 'CachePatterns')
            $versionRegex = [string](Get-WinMintPayloadSpecValue -Spec $spec -Name 'VersionRegex' -Default '')
            $hashLabel = [string](Get-WinMintPayloadSpecValue -Spec $spec -Name 'HashLabel' -Default $name)
            if ([string]::IsNullOrWhiteSpace($name) -or $patterns.Count -eq 0) {
                throw "Invalid cached payload spec for $RepoSlug; Name and CachePatterns are required."
            }
            $results.Add((Resolve-WinMintCachedPayload `
                        -Name $name `
                        -Patterns $patterns `
                        -VersionRegex $versionRegex `
                        -HashLabel $hashLabel)) | Out-Null
        }
        return $results.ToArray()
    }
    catch {
        throw "$RepoSlug payload-set resolution failed. Release error: $($releaseError.Exception.Message) Cache error: $($_.Exception.Message)"
    }
}

function Resolve-WinMintGitHubReleasePayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$RepoSlug,
        [Parameter(Mandatory)][scriptblock]$AssetSelector,
        [Parameter(Mandatory)][string[]]$CachePatterns,
        [hashtable]$Headers = @{ 'User-Agent' = 'WinMint/1.0' },
        [string]$VersionRegex = '',
        [string]$HashLabel = ''
    )

    $releaseError = $null
    try {
        $release = Invoke-RestMethod -Verbose:$false -Uri "https://api.github.com/repos/$RepoSlug/releases/latest" -Headers $Headers
        $asset = Select-WinMintGitHubReleaseAsset -Name $Name -Release $release -AssetSelector $AssetSelector
        $path = Invoke-WebRequestCachedFile -Uri $asset.browser_download_url -CacheFileName $asset.name -Headers $Headers
        return New-WinMintPayloadResult `
            -Name $Name `
            -Path $path `
            -SourceUrl ([string]$asset.browser_download_url) `
            -Version ([string]$release.tag_name) `
            -AssetName ([string]$asset.name) `
            -SourceStatus release `
            -CleanupPolicy keep `
            -HashLabel $HashLabel
    }
    catch {
        $releaseError = $_
        if (Get-Command LogWarn -ErrorAction SilentlyContinue) {
            LogWarn "$Name release lookup failed; trying cached payload. $($releaseError.Exception.Message)"
        }
    }

    try {
        return Resolve-WinMintCachedPayload `
            -Name $Name `
            -Patterns $CachePatterns `
            -VersionRegex $VersionRegex `
            -HashLabel $HashLabel
    }
    catch {
        throw "$Name payload resolution failed. Release error: $($releaseError.Exception.Message) Cache error: $($_.Exception.Message)"
    }
}
