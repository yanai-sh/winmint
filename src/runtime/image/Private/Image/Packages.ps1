#Requires -Version 7.3

function Copy-WinMintPayloadDirectoryChildren {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SourceDir,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$DestinationDir
    )

    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
        throw "Payload source directory not found: $SourceDir"
    }

    $null = New-Item -ItemType Directory -Path $DestinationDir -Force -ErrorAction Stop
    foreach ($item in @(Get-ChildItem -LiteralPath $SourceDir -Force -ErrorAction Stop)) {
        Copy-Item -LiteralPath $item.FullName -Destination $DestinationDir -Recurse -Force -ErrorAction Stop
    }
}

function Install-OfflinePowerShell7 {
    <# <summary>Extract GitHub PowerShell release zip into the offline image so specialize / SetupComplete / FirstLogon can run pwsh.exe.</summary> #>
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [Parameter(Mandatory)][string]$TargetArch
    )
    Write-SectionHeader 'Image: PowerShell 7'
    Invoke-Action 'Installing PowerShell 7 into the offline image (pwsh for setup scripts)' {
        LogVerbose "Mount: $MountDir | arch: $TargetArch"
        $zip = $null
        $payload = $null
        $expand = $null
        try {
            $suffix = switch ($TargetArch) {
                'arm64' { 'win-arm64' }
                'x86' { 'win-x86' }
                default { 'win-x64' }
            }
            $payload = Resolve-WinMintGitHubReleasePayload `
                -Name 'PowerShell 7' `
                -RepoSlug 'PowerShell/PowerShell' `
                -Headers @{ 'User-Agent' = 'WinMint/1.0' } `
                -CachePatterns @("PowerShell-*-$suffix.zip") `
                -VersionRegex 'PowerShell-(?<Version>\d+\.\d+\.\d+)-' `
                -HashLabel 'PowerShell 7' `
                -AssetSelector {
                    param($Asset, $Release)
                    [void]$Release
                    $assetName = [string]$Asset.name
                    if ($assetName -match ('PowerShell-\d+\.\d+\.\d+-' + [regex]::Escape($suffix) + '\.zip$')) { return 300 }
                    if ($assetName -like "*-$suffix.zip") { return 200 }
                    if ($suffix -eq 'win-x86' -and $assetName -like '*-win-x64.zip') { return 100 }
                    return 0
                }
            $zip = [string]$payload.Path
            Add-WinMintManifestPayloadFact -Payload $payload
            $expand = Join-Path (Get-Win11IsoProcessTempPath) ('pwsh7_expand_' + [Guid]::NewGuid().ToString('n'))
            Expand-Archive -LiteralPath $zip -DestinationPath $expand -Force
            $sourceDir = $expand
            if (-not (Test-Path -LiteralPath (Join-Path $sourceDir 'pwsh.exe'))) {
                $inner = @(Get-ChildItem -LiteralPath $expand -Directory -ErrorAction Stop |
                    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'pwsh.exe') })
                if ($inner.Count -ne 1) {
                    throw 'PowerShell zip: could not locate pwsh.exe at archive root or in a single top-level directory.'
                }
                $sourceDir = $inner[0].FullName
            }

            $dest = Join-Path $MountDir 'Program Files\PowerShell\7'
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction Stop }
            Copy-WinMintPayloadDirectoryChildren -SourceDir $sourceDir -DestinationDir $dest

            $pwshExe = Join-Path $dest 'pwsh.exe'
            if (-not (Test-Path -LiteralPath $pwshExe)) { throw "pwsh.exe missing after staging: $pwshExe" }
            LogOK "PowerShell 7 staged in the offline image (release: $($payload.Version))."
            LogVerbose "$pwshExe (release asset: $($payload.AssetName))"
        }
        catch {
            LogWarn "PowerShell 7 staging failed; setup scripts will fall back to Windows PowerShell. $($_.Exception.Message)"
        }
        finally {
            Remove-WinMintPayloadResult -Payload $payload
            if ($expand -and (Test-Path -LiteralPath $expand)) { Remove-Item -LiteralPath $expand -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Get-WinMintViveToolReleaseAsset {
    param(
        [Parameter(Mandatory)][string]$TargetArch,
        [hashtable]$Headers = @{ 'User-Agent' = 'WinMint/1.0' }
    )

    $rel = Invoke-RestMethod -Verbose:$false -Uri 'https://api.github.com/repos/thebookisclosed/ViVe/releases/latest' -Headers $Headers
    $zipAssets = @($rel.assets | Where-Object { $_.name -match '\.zip$' })
    if ($zipAssets.Count -eq 0) { throw "ViVeTool release $($rel.tag_name) has no .zip assets." }

    $asset = if ($TargetArch -eq 'arm64') {
        $zipAssets | Where-Object { $_.name -match '(?i)(SnapdragonArm64|ARM64CLR|Arm64)' } | Select-Object -First 1
    } else {
        $zipAssets | Where-Object { $_.name -match '(?i)IntelAmd' } | Select-Object -First 1
    }
    if (-not $asset -and $TargetArch -ne 'arm64') {
        $asset = $zipAssets | Where-Object { $_.name -notmatch '(?i)(SnapdragonArm64|ARM64CLR|Arm64)' } | Select-Object -First 1
    }
    # Permissive ARM64 fallback: if upstream renames or drops a known prefix
    # (e.g., adds ARM64EC, drops 'Snapdragon'), accept any .zip whose name
    # contains 'arm64' in any casing. The earlier filter to .zip assets
    # already excludes .txt / .sha256 / signature sidecars.
    if (-not $asset -and $TargetArch -eq 'arm64') {
        $asset = $zipAssets | Where-Object { $_.name -match '(?i)arm64' } | Select-Object -First 1
    }
    if (-not $asset) {
        $available = ($zipAssets | ForEach-Object { $_.name }) -join ', '
        throw "ViVeTool release $($rel.tag_name) has no asset matching target architecture '$TargetArch'. Available: $available"
    }

    [pscustomobject]@{ Release = $rel; Asset = $asset }
}

function Install-OfflineViveTool {
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [Parameter(Mandatory)][string]$TargetArch
    )
    Write-SectionHeader 'Image: ViVeTool'
    Invoke-Action 'Staging ViVeTool for SetupComplete feature overrides' {
        LogVerbose "Mount: $MountDir | arch: $TargetArch"
        $zip = $null
        $payload = $null
        $expand = $null
        try {
            $headers = @{
                'User-Agent' = 'WinMint/1.0 (ViVeTool)'
                'Accept' = 'application/vnd.github+json'
                'X-GitHub-Api-Version' = '2022-11-28'
            }
            $payload = Resolve-WinMintGitHubReleasePayload `
                -Name 'ViVeTool' `
                -RepoSlug 'thebookisclosed/ViVe' `
                -Headers $headers `
                -CachePatterns @(Get-WinMintViveToolCachePattern -Architecture $TargetArch) `
                -VersionRegex 'ViVeTool-(?<Version>v?\d+\.\d+\.\d+)' `
                -HashLabel 'ViVeTool' `
                -AssetSelector {
                    param($Asset, $Release)
                    [void]$Release
                    $assetName = [string]$Asset.name
                    if ($assetName -notmatch '\.zip$') { return $false }
                    if ($TargetArch -eq 'arm64') {
                        return ($assetName -match '(?i)(SnapdragonArm64|ARM64CLR|Arm64|arm64)')
                    }
                    if ($assetName -match '(?i)IntelAmd') { return $true }
                    return ($assetName -notmatch '(?i)(SnapdragonArm64|ARM64CLR|Arm64)')
                }
            $zip = [string]$payload.Path
            Add-WinMintManifestPayloadFact -Payload $payload
            $expand = Join-Path (Get-Win11IsoProcessTempPath) ('vivetool_expand_' + [Guid]::NewGuid().ToString('n'))
            Expand-Archive -LiteralPath $zip -DestinationPath $expand -Force
            $exe = Get-ChildItem -LiteralPath $expand -Recurse -Filter 'ViVeTool.exe' -File -ErrorAction Stop |
                Select-Object -First 1
            if (-not $exe) { throw 'ViVeTool.exe missing after extracting release archive.' }

            $dest = Join-Path $MountDir 'Windows\Setup\Scripts\ViVeTool'
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction Stop }
            Copy-WinMintPayloadDirectoryChildren -SourceDir $exe.DirectoryName -DestinationDir $dest
            if (-not (Test-Path -LiteralPath (Join-Path $dest 'ViVeTool.exe'))) {
                throw "ViVeTool.exe missing after staging: $dest"
            }

            LogOK "ViVeTool staged for setup-time feature overrides (release: $($payload.Version))."
            LogVerbose "Release asset: $($payload.AssetName)"
        }
        catch {
            LogWarn "ViVeTool staging failed; virtual desktop flyout override will be skipped. $($_.Exception.Message)"
        }
        finally {
            Remove-WinMintPayloadResult -Payload $payload
            if ($expand -and (Test-Path -LiteralPath $expand)) {
                Remove-Item -LiteralPath $expand -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Remove-NonEnglishLanguageFeature {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [string[]]$PreserveLanguages = @('en-us'),
        # Secondary INPUT languages (keyboards). Their Basic-typing feature package is kept so
        # the keyboard has basic typing/spellcheck support; their other features
        # (Handwriting/OCR/Speech/TextToSpeech) are still removed. The display language stays
        # whatever PreserveLanguages holds (en-US).
        [string[]]$InputLanguages = @()
    )
    Write-SectionHeader 'Image: non-English language components'
    $cmdlet = $PSCmdlet
    Invoke-Action 'Removing non-English language feature packages from the image' {
        LogVerbose "Mount: $MountDir"
        $preserve = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($language in @('en-us') + @($PreserveLanguages)) {
            if ($language -match '^[a-z]{2,3}(?:-[a-z]+)*$') {
                $null = $preserve.Add($language.ToLowerInvariant())
            }
        }
        $inputPrimary = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($lang in @($InputLanguages)) {
            $primary = (([string]$lang) -split '-')[0]
            if ($primary) { $null = $inputPrimary.Add($primary.ToLowerInvariant()) }
        }
        LogVerbose "Preserving language feature packages for: $(@($preserve) -join ', '); Basic-only for input languages: $(@($inputPrimary) -join ', ')"
        $pkgOutput = try { @((Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Get-Packages')).Output) } catch { return }
        # Group 1 = feature type (Basic/Fonts/Handwriting/OCR/Speech/TextToSpeech); group 2 =
        # language token. NOTE: Fonts use a 4-letter script code (e.g. 'Hebr') that does not
        # match this 2-3-letter token, so font packages are never matched/removed - non-Latin
        # text (Hebrew, etc.) renders regardless.
        $languageFeaturePattern = 'Microsoft-Windows-LanguageFeatures-(.+?)-([a-z]{2,3}(?:-[a-z]+)*)-Package~'
        $toRemove = $pkgOutput |
            Where-Object {
                if ($_ -notmatch $languageFeaturePattern) { return $false }
                $featureType = $matches[1]; $token = $matches[2]
                if ($preserve.Contains($token)) { return $false }
                # Keep Basic typing for secondary input languages (keyboard + basic typing);
                # other feature types for those languages are still removed.
                if ($featureType -ieq 'Basic' -and $inputPrimary.Contains((($token -split '-')[0]))) { return $false }
                return $true
            } |
            ForEach-Object {
                if ($_ -match 'Package Identity\s*:\s*(.+)$') { $matches[1].Trim() }
            }
        $removedPackages = [System.Collections.Generic.List[string]]::new()
        foreach ($pkg in $toRemove) {
            if ($cmdlet.ShouldProcess($pkg, 'Remove-WindowsPackage via DISM')) {
                Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Remove-Package', "/PackageName:$pkg", '/Quiet', '/NoRestart') | Out-Null
                $removedPackages.Add($pkg) | Out-Null
            }
        }
        Set-WinMintManifestLanguagePackageRemovalFacts -PackageNames $removedPackages.ToArray()
    }
}

function Import-WinMintDefaultAppAssociations {
    # Apply default file/protocol associations to the offline image the SUPPORTED way. Unlike
    # a hash-less HKCU\...\UserChoice\ProgId write (which Windows 11 rejects/resets), an
    # Import-DefaultAppAssociations XML becomes the per-new-user default and is honored.
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [ValidateNotNullOrEmpty()][string]$XmlPath
    )
    if (-not (Test-Path -LiteralPath $XmlPath)) {
        LogVerbose "DefaultAppAssociations XML not found ($XmlPath); skipping."
        return
    }
    Write-SectionHeader 'Image: default app associations'
    Invoke-Action 'Importing default app associations into the image' {
        LogVerbose "Mount: $MountDir | Associations: $XmlPath"
        Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", "/Import-DefaultAppAssociations:$XmlPath") | Out-Null
        LogOK "Imported default app associations from $(Split-Path -Leaf $XmlPath)."
    }
}

function Get-WinMintOfflineUpdatePackageFiles {
    param(
        [Parameter(Mandatory)][string]$PayloadRoot,
        [Parameter(Mandatory)][string]$Category
    )

    $categoryDir = Join-Path $PayloadRoot $Category
    if (-not (Test-Path -LiteralPath $categoryDir -PathType Container)) { return @() }
    @(
        Get-ChildItem -LiteralPath $categoryDir -Recurse -File -ErrorAction Stop |
            Where-Object { $_.Extension -in @('.msu', '.cab') } |
            Sort-Object FullName |
            ForEach-Object { $_.FullName }
    )
}

function Get-WinMintOfflineUpdateAppxFiles {
    param([Parameter(Mandatory)][string]$PayloadRoot)

    $appxDir = Join-Path $PayloadRoot 'appx'
    if (-not (Test-Path -LiteralPath $appxDir -PathType Container)) { return @() }
    @(
        Get-ChildItem -LiteralPath $appxDir -Recurse -File -ErrorAction Stop |
            Where-Object { $_.Extension -in @('.msixbundle', '.appxbundle', '.msix', '.appx') } |
            Sort-Object FullName |
            ForEach-Object { $_.FullName }
    )
}

function Get-WinMintOfflineUpdateAppxDependencyFiles {
    param(
        [Parameter(Mandatory)][string]$PayloadRoot,
        [Parameter(Mandatory)][string]$TargetArch
    )

    $dependencyRoot = Join-Path $PayloadRoot 'appx-dependencies'
    if (-not (Test-Path -LiteralPath $dependencyRoot -PathType Container)) { return @() }
    $archFolder = switch ($TargetArch) {
        'arm64' { 'arm64' }
        'amd64' { 'x64' }
        'x64' { 'x64' }
        'x86' { 'x86' }
        default { $TargetArch }
    }
    $candidateRoots = @(
        Join-Path $dependencyRoot $archFolder
        $dependencyRoot
    ) | Select-Object -Unique

    @(
        foreach ($root in $candidateRoots) {
            if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
            Get-ChildItem -LiteralPath $root -File -ErrorAction Stop |
                Where-Object { $_.Extension -in @('.appx', '.msix') } |
                Sort-Object FullName |
                ForEach-Object { $_.FullName }
        }
    ) | Select-Object -Unique
}

function Invoke-WinMintOfflineUpdatePackages {
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [Parameter(Mandatory)]$Updates
    )

    $payloadRoot = [string]$Updates.PayloadRoot
    $categories = @(
        [pscustomobject]@{ Id = 'packages'; Enabled = [bool]$Updates.QualitySecurity; Label = 'quality/security packages' }
        [pscustomobject]@{ Id = 'dynamic-update'; Enabled = [bool]$Updates.DynamicUpdate; Label = 'dynamic update packages' }
        [pscustomobject]@{ Id = 'defender'; Enabled = [bool]$Updates.Defender; Label = 'Defender packages' }
        [pscustomobject]@{ Id = 'dotnet'; Enabled = [bool]$Updates.DotNet; Label = '.NET packages' }
    )

    $appliedCount = 0
    foreach ($category in $categories) {
        if (-not [bool]$category.Enabled) {
            Add-WinMintManifestUpdateSkippedFact -Message "$($category.Id): disabled"
            continue
        }
        $packages = @(Get-WinMintOfflineUpdatePackageFiles -PayloadRoot $payloadRoot -Category ([string]$category.Id))
        if ($packages.Count -eq 0) {
            Add-WinMintManifestUpdateSkippedFact -Message "$($category.Id): no .msu/.cab payloads found"
            continue
        }
        foreach ($package in $packages) {
            try {
                Log "Applying $($category.Label): $(Split-Path -Leaf $package)"
                Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Add-Package', "/PackagePath:$package", '/Quiet', '/NoRestart') | Out-Null
                Add-WinMintManifestUpdatePackageFact -Category ([string]$category.Id) -Path $package
                $appliedCount++
            }
            catch {
                Add-WinMintManifestUpdateFailureFact -Category ([string]$category.Id) -Path $package -ErrorMessage $_.Exception.Message
                throw
            }
        }
    }

    return $appliedCount
}

function Invoke-WinMintOfflineUpdateAppx {
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [Parameter(Mandatory)]$Updates,
        [Parameter(Mandatory)][string]$TargetArch
    )

    if (-not [bool]$Updates.ProvisionedApps) {
        Add-WinMintManifestUpdateSkippedFact -Message 'appx: disabled'
        return 0
    }

    $payloadRoot = [string]$Updates.PayloadRoot
    $bundles = @(Get-WinMintOfflineUpdateAppxFiles -PayloadRoot $payloadRoot)
    if ($bundles.Count -eq 0) {
        Add-WinMintManifestUpdateSkippedFact -Message 'appx: no MSIX/AppX payloads found'
        return 0
    }
    $dependencies = @(Get-WinMintOfflineUpdateAppxDependencyFiles -PayloadRoot $payloadRoot -TargetArch $TargetArch)

    $provisionedCount = 0
    foreach ($bundle in $bundles) {
        try {
            Log "Provisioning app package: $(Split-Path -Leaf $bundle)"
            $dismArgs = @('/English', "/Image:$MountDir", '/Add-ProvisionedAppxPackage', "/PackagePath:$bundle")
            foreach ($dependency in $dependencies) {
                $dismArgs += "/DependencyPackagePath:$dependency"
            }
            $dismArgs += '/SkipLicense'
            Invoke-DismExe -Arguments $dismArgs | Out-Null
            Add-WinMintManifestUpdateAppxFact -Path $bundle -DependencyCount $dependencies.Count
            $provisionedCount++
        }
        catch {
            Add-WinMintManifestUpdateFailureFact -Category 'appx' -Path $bundle -ErrorMessage $_.Exception.Message
            throw
        }
    }

    return $provisionedCount
}

function Invoke-WinMintOfflineImageUpdates {
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [Parameter(Mandatory)]$Updates,
        [Parameter(Mandatory)][string]$TargetArch
    )

    if ($null -eq $Updates -or [string]$Updates.Mode -eq 'None') { return }
    if ([string]$Updates.Mode -ne 'Stable25H2') {
        throw "Unsupported image update mode: $($Updates.Mode)"
    }
    if ([bool]$Updates.IncludeOptionalPreviews) {
        throw 'Optional preview updates are not allowed in Stable25H2 image servicing.'
    }

    Write-SectionHeader 'Image: stable 25H2 update payloads'
    Invoke-Action 'Applying explicit stable 25H2 update payloads to the offline image' -SpectreProgressIndeterminate {
        LogVerbose "Mount: $MountDir | payloadRoot: $($Updates.PayloadRoot)"
        $packageCount = Invoke-WinMintOfflineUpdatePackages -MountDir $MountDir -Updates $Updates
        $appxCount = Invoke-WinMintOfflineUpdateAppx -MountDir $MountDir -Updates $Updates -TargetArch $TargetArch
        if (($packageCount + $appxCount) -eq 0) {
            throw "Stable25H2 update mode was selected, but no update payloads were applied from '$($Updates.PayloadRoot)'."
        }
        LogOK "Applied $packageCount package payload(s) and provisioned $appxCount app package(s)."
    }
}

function Save-ImageWithCleanup {
    param([ValidateNotNullOrEmpty()][string]$MountDir)
    Write-SectionHeader 'Image: cleanup and save' -Accent Yellow -RuleColor Grey -DimLine 'Component cleanup and save can take several minutes; the bar below is normal.'
    Invoke-Action 'Running DISM component cleanup on the mounted Windows image' -SpectreProgressIndeterminate {
        LogVerbose "Mount: $MountDir"
        Set-WinMintManifestComponentCleanupFact
        Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Cleanup-Image', '/StartComponentCleanup') | Out-Null
        LogOK 'DISM component cleanup finished.'
    }
    Invoke-Action 'Saving and dismounting the Windows image (commit can take several minutes)' -SpectreProgressIndeterminate {
        LogVerbose "Mount: $MountDir"
        Save-WinMintImageMount -MountDir $MountDir
        LogOK 'Windows image saved and dismounted.'
    }
}

function Export-SingleEdition {
    param([ValidateNotNullOrEmpty()][string]$LocalWim, [int]$SelectedWimIndex, [ValidateNotNullOrEmpty()][string]$SelectedEdition)
    Write-SectionHeader "Image: export $SelectedEdition"
    Invoke-Action "Exporting a single-edition install.wim ($SelectedEdition)" {
        LogVerbose "Source WIM: $LocalWim | index $SelectedWimIndex"
        $exportWim = Join-Path (Split-Path $LocalWim -Parent) 'install_export.wim'
        $null = Export-WindowsImage -SourceImagePath $LocalWim -SourceIndex $SelectedWimIndex -DestinationImagePath $exportWim -ErrorAction Stop
        Remove-Item -LiteralPath $LocalWim -Force -ErrorAction Stop
        Rename-Item -LiteralPath $exportWim -NewName 'install.wim' -Force -ErrorAction Stop
    }
}

function Get-BuildHostProcessorArchitecture {
    <# <summary>Normalized host CPU for picking oscdimg: amd64 | arm64 | x86.</summary> #>
    $a = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    switch ($a.ToString()) {
        'X64' { return 'amd64' }
        'Arm64' { return 'arm64' }
        'X86' { return 'x86' }
        default { return $a.ToString().ToLowerInvariant() }
    }
}

function Select-PreferredOscdimgExe {
    <# <summary>Pick best oscdimg for this machine: native host architecture first, with ADK amd64/x86 fallbacks.</summary> #>
    param(
        [string[]]$CandidatePaths,
        [Parameter(Mandatory)][string]$HostProcessorArch
    )
    $p = @($CandidatePaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Sort-Object -Unique)
    if ($p.Count -eq 0) { return $null }
    if ($p.Count -eq 1) { return $p[0] }

    $scorePath = {
        param([string]$Path, [string]$HostArch)
        $score = 0
        if ($Path -match '(?i)[\\/]amd64[\\/]Oscdimg[\\/]oscdimg\.exe$') { $score = 800 }
        elseif ($Path -match '(?i)[\\/]amd64[\\/].*oscdimg\.exe$') { $score = 700 }
        elseif ($Path -match '(?i)[\\/]arm64[\\/]Oscdimg[\\/]oscdimg\.exe$') { $score = 800 }
        elseif ($Path -match '(?i)[\\/]arm64[\\/].*oscdimg\.exe$') { $score = 700 }
        elseif ($Path -match '(?i)[\\/]x86[\\/]Oscdimg[\\/]oscdimg\.exe$') { $score = 600 }
        elseif ($Path -match '(?i)[\\/]x86[\\/].*oscdimg\.exe$') { $score = 500 }
        else { $score = 100 }

        if ($HostArch -eq 'arm64' -and $Path -match '(?i)[\\/]arm64[\\/]') { $score += 1000 }
        elseif ($HostArch -eq 'amd64' -and $Path -match '(?i)[\\/]amd64[\\/]') { $score += 1000 }
        elseif ($HostArch -eq 'x86' -and $Path -match '(?i)[\\/]x86[\\/]') { $score += 1000 }
        return $score
    }

    return ($p | ForEach-Object {
            [pscustomobject]@{ Path = $_; Score = & $scorePath $_ $HostProcessorArch }
        } | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Path'; Descending = $false } | Select-Object -First 1).Path
}

function Resolve-OscdimgBootdataFilePath {
    <# <summary>Absolute path for -bootdata without embedded double-quotes (PowerShell/native quoting doubles them and breaks oscdimg). Uses 8.3 short path if the path contains spaces.</summary> #>
    param([Parameter(Mandatory)][string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath)) { throw "Boot file not found: $LiteralPath" }
    $full = [IO.Path]::GetFullPath($LiteralPath)
    if ($full -notmatch '\s') { return $full }
    try {
        $short = (New-Object -ComObject Scripting.FileSystemObject).GetFile($full).ShortPath
        if ($short -and ($short -notmatch '\s')) { return $short }
    }
    catch {
        Write-Verbose "Short path for oscdimg boot file failed: $($_.Exception.Message)"
    }
    throw "Boot file path contains spaces and could not be shortened for oscdimg. Use a build/output path without spaces, or install the Windows ADK amd64 Oscdimg. Path: $full"
}

function Get-OscdimgBootDataValue {
    <# <summary>Builds oscdimg boot sector layout from install.wim architecture.</summary> #>
    param(
        [Parameter(Mandatory)][string]$IsoContentsRoot,
        [Parameter(Mandatory)][string]$ImageArch
    )
    $efisysNoPrompt = Join-Path $IsoContentsRoot 'efi\microsoft\boot\efisys_noprompt.bin'
    $efisys = if (Test-Path -LiteralPath $efisysNoPrompt) {
        $efisysNoPrompt
    }
    else {
        Join-Path $IsoContentsRoot 'efi\microsoft\boot\efisys.bin'
    }
    if (-not (Test-Path -LiteralPath $efisys)) { throw "Missing UEFI boot file for oscdimg: $efisys" }
    $efiBootName = Split-Path -Leaf $efisys
    if ($ImageArch -eq 'arm64') {
        LogOK 'ISO boot layout: UEFI only (expected for ARM64 media).'
        LogVerbose "oscdimg -bootdata: $efiBootName only (no legacy BIOS sector on ARM64)."
        $efiTok = Resolve-OscdimgBootdataFilePath -LiteralPath $efisys
        return ('1#pEF,e,b{0}' -f $efiTok)
    }
    $etfs = Join-Path $IsoContentsRoot 'boot\etfsboot.com'
    $efiTok = Resolve-OscdimgBootdataFilePath -LiteralPath $efisys
    if (Test-Path -LiteralPath $etfs) {
        LogOK 'ISO boot layout: legacy BIOS + UEFI (El Torito + EFI boot).'
        LogVerbose "oscdimg -bootdata: etfsboot.com + $efiBootName."
        $etfsTok = Resolve-OscdimgBootdataFilePath -LiteralPath $etfs
        return ('2#p0,e,b{0}#pEF,e,b{1}' -f $etfsTok, $efiTok)
    }
    LogWarn 'boot\etfsboot.com not found on the staged tree; ISO will be UEFI-only (no legacy BIOS boot sector).'
    return ('1#pEF,e,b{0}' -f $efiTok)
}

function Resolve-OscdimgPath {
    $hostArch = Get-BuildHostProcessorArchitecture
    # Resolve via the environment instead of a hardcoded C: drive; Windows and
    # the ADK can live on non-C: volumes.
    $kitsCandidates = Get-WinMintWindowsKitsOscdimgCandidates
    $oscdimg = Select-PreferredOscdimgExe -CandidatePaths $kitsCandidates -HostProcessorArch $hostArch
    if (-not $oscdimg) {
        $wgCandidates = Get-WinMintInstalledWingetOscdimgCandidates
        $oscdimg = Select-PreferredOscdimgExe -CandidatePaths $wgCandidates -HostProcessorArch $hostArch
    }
    if (-not $oscdimg) {
        $downloadedCandidates = Resolve-WinMintWingetDownloadedOscdimgCandidates
        $oscdimg = Select-PreferredOscdimgExe -CandidatePaths $downloadedCandidates -HostProcessorArch $hostArch
        if ($oscdimg) {
            LogVerbose "oscdimg from dependency cache: $oscdimg"
        }
    }
    if (-not $oscdimg) {
        try {
            $wingetCmd = Get-WinMintWingetExePath
            if (-not $wingetCmd) {
                throw 'winget.exe not found.'
            }
            Install-WinMintWindowsAdkForOscdimg -WingetPath $wingetCmd
            $oscdimg = Select-PreferredOscdimgExe -CandidatePaths (Get-WinMintWindowsKitsOscdimgCandidates) -HostProcessorArch $hostArch
        }
        catch {
            Write-Verbose "Windows ADK winget install failed: $($_.Exception.Message)"
        }
    }
    if (-not $oscdimg) {
        throw @(
            'oscdimg.exe not found. Install the Windows ADK Deployment Tools,'
            'or ensure winget can install Microsoft.WindowsADK with --architecture x64.'
            'WinMint tries Microsoft.OSCDIMG first, then Microsoft.WindowsADK latest, then version 10.1.26100.2454.'
        ) -join ' '
    }
    return $oscdimg
}
