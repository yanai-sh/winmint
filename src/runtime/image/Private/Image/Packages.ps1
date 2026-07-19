#Requires -Version 7.6

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

function Add-OfflineMachinePathEntry {
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$MountDir,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Entry
    )

    $hiveKey = 'WinMintOfflineSYSTEM'
    $systemHive = Join-Path $MountDir 'Windows\System32\config\SYSTEM'
    $envKey = "HKLM\$hiveKey\ControlSet001\Control\Session Manager\Environment"
    $null = & reg.exe load "HKLM\$hiveKey" $systemHive
    try {
        $current = ''
        $query = @(& reg.exe query $envKey /v Path 2>$null)
        foreach ($line in $query) {
            if ($line -match 'REG_(?:EXPAND_)?SZ\s+(.+)$') {
                $current = $matches[1].Trim()
                break
            }
        }
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($part in ($current -split ';')) {
            if (-not [string]::IsNullOrWhiteSpace($part)) { $parts.Add($part.Trim()) | Out-Null }
        }
        $alreadyPresent = @(
            $parts |
                Where-Object {
                    $_ -ieq $Entry -or
                    $_ -ieq ($Entry -replace '%ProgramFiles%', 'C:\Program Files') -or
                    $_ -ieq (Join-Path $MountDir ($Entry -replace '%ProgramFiles%\\', 'Program Files\'))
                }
        ).Count -gt 0
        if (-not $alreadyPresent) {
            $parts.Add($Entry) | Out-Null
            $null = & reg.exe add $envKey /v Path /t REG_EXPAND_SZ /d ($parts -join ';') /f
        }
    }
    finally {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds 200
        $null = & reg.exe unload "HKLM\$hiveKey"
    }
}

function Assert-OfflinePowerShell7Staged {
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$MountDir)

    $pwshExe = Join-Path $MountDir 'Program Files\PowerShell\7\pwsh.exe'
    if (-not (Test-Path -LiteralPath $pwshExe -PathType Leaf)) {
        throw "PowerShell 7 is missing from the offline image: $pwshExe. SetupComplete and FirstLogon require bundled PowerShell 7; rebuild without the serviced-WIM cache or refresh the payload cache."
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
            Add-OfflineMachinePathEntry -MountDir $MountDir -Entry '%ProgramFiles%\PowerShell\7'
            Assert-OfflinePowerShell7Staged -MountDir $MountDir
            LogOK "PowerShell 7 staged ($($payload.Version))"
            LogVerbose "$pwshExe (release asset: $($payload.AssetName))"
        }
        catch {
            throw "PowerShell 7 staging failed; build cannot continue because setup and FirstLogon require bundled PowerShell 7. $($_.Exception.Message)"
        }
        finally {
            Remove-WinMintPayloadResult -Payload $payload
            if ($expand -and (Test-Path -LiteralPath $expand)) { Remove-Item -LiteralPath $expand -Recurse -Force -ErrorAction SilentlyContinue }
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

function Select-WinMintQualitySecurityTargetPackage {
    param(
        [Parameter(Mandatory)][string]$PayloadRoot,
        [Parameter(Mandatory)][string[]]$Packages
    )

    if ($Packages.Count -eq 1) { return $Packages[0] }

    $manifestPath = Join-Path $PayloadRoot 'UpdatePayloadManifest.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $qualityPayloads = @(
                @($manifest.payloads) |
                    Where-Object { [string]$_.category -eq 'packages' -and [string]$_.kind -eq 'QualitySecurity' }
            )
            $targetKb = ''
            foreach ($payload in $qualityPayloads) {
                if ([string]$payload.title -match '(?i)\(KB(?<kb>\d+)\)') {
                    $targetKb = [string]$Matches['kb']
                    break
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($targetKb)) {
                $target = @($qualityPayloads | Where-Object { [string]$_.fileName -match "kb$targetKb" } | Select-Object -First 1)
                if ($target.Count -gt 0 -and (Test-Path -LiteralPath ([string]$target[0].path) -PathType Leaf)) {
                    return [string]$target[0].path
                }
            }
        }
        catch {
            LogVerbose "Quality update target selection manifest probe failed: $($_.Exception.Message)"
        }
    }

    return @(
        $Packages |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Sort-Object @{ Expression = { (Get-Item -LiteralPath $_).Length }; Descending = $true },
            @{ Expression = { [IO.Path]::GetFileName($_) }; Descending = $true } |
            Select-Object -First 1
    )[0]
}

function Invoke-WinMintOfflineUpdatePackages {
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [Parameter(Mandatory)]$Updates
    )

    $payloadRoot = [string]$Updates.PayloadRoot
    $categories = @(
        [pscustomobject]@{ Id = 'packages'; Enabled = [bool]$Updates.QualitySecurity; Label = 'quality/security packages' }
        [pscustomobject]@{ Id = 'dotnet'; Enabled = [bool]$Updates.DotNet; Label = '.NET packages' }
    )

    $appliedCount = 0
    if ([bool]$Updates.DynamicUpdate) {
        $dynamicPackages = @(Get-WinMintOfflineUpdatePackageFiles -PayloadRoot $payloadRoot -Category 'dynamic-update')
        if ($dynamicPackages.Count -gt 0) {
            Add-WinMintManifestUpdateSkippedFact -Message 'dynamic-update: acquired for setup media servicing; not applicable to install.wim Add-Package'
        }
        else {
            Add-WinMintManifestUpdateSkippedFact -Message 'dynamic-update: no .msu/.cab payloads found'
        }
    }
    else {
        Add-WinMintManifestUpdateSkippedFact -Message 'dynamic-update: disabled'
    }
    if ([bool]$Updates.Defender) {
        $defenderPackages = @(Get-WinMintOfflineUpdatePackageFiles -PayloadRoot $payloadRoot -Category 'defender')
        if ($defenderPackages.Count -gt 0) {
            Add-WinMintManifestUpdateSkippedFact -Message 'defender: acquired for Microsoft DefenderUpdateWinImage.ps1 flow; not applicable to install.wim Add-Package'
        }
        else {
            Add-WinMintManifestUpdateSkippedFact -Message 'defender: no .msu/.cab payloads found'
        }
    }
    else {
        Add-WinMintManifestUpdateSkippedFact -Message 'defender: disabled'
    }

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
        if ([string]$category.Id -eq 'packages') {
            $targetPackage = Select-WinMintQualitySecurityTargetPackage -PayloadRoot $payloadRoot -Packages $packages
            try {
                Log "Applying $($category.Label)..."
                LogVerbose "Applying $($category.Label): $(Split-Path -Leaf $targetPackage)"
                if ($packages.Count -gt 1) {
                    LogVerbose 'Checkpoint cumulative update chain detected; DISM is pointed at the latest target MSU so it can discover checkpoint MSUs in the same folder.'
                }
                Invoke-WinMintDismAddUpdatePackage -MountDir $MountDir -PackagePath $targetPackage
                foreach ($package in $packages) {
                    Add-WinMintManifestUpdatePackageFact -Category ([string]$category.Id) -Path $package
                }
                $appliedCount += $packages.Count
            }
            catch {
                Add-WinMintManifestUpdateFailureFact -Category ([string]$category.Id) -Path $targetPackage -ErrorMessage $_.Exception.Message
                throw
            }
            continue
        }
        Log "Applying $($category.Label)..."
        foreach ($package in $packages) {
            try {
                LogVerbose "Applying $($category.Label): $(Split-Path -Leaf $package)"
                Invoke-WinMintDismAddUpdatePackage -MountDir $MountDir -PackagePath $package
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

function Invoke-WinMintDismAddUpdatePackage {
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [Parameter(Mandatory)][string]$PackagePath
    )

    $arguments = @('/English', "/Image:$MountDir", '/Add-Package', "/PackagePath:$PackagePath", '/Quiet', '/NoRestart')
    $attempt = 0
    while ($attempt -lt 2) {
        $attempt++
        try {
            Invoke-DismExe -Arguments $arguments | Out-Null
            return
        }
        catch {
            $message = [string]$_.Exception.Message
            $retryableServicingTransition = (
                $message -match '(?i)(exit\s+552|Error:\s*552|pending updates to servicing components|Try the command again)'
            )
            if ($attempt -lt 2 -and $retryableServicingTransition) {
                LogWarn "DISM reported servicing-component transition while adding $(Split-Path -Leaf $PackagePath); retrying once."
                Start-Sleep -Seconds 5
                continue
            }
            throw
        }
    }
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
            LogVerbose "Provisioning app package: $(Split-Path -Leaf $bundle)"
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
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [ValidateSet('Max', 'Fast', 'None')][string]$ImageCompression = 'Max',
        [switch]$SkipComponentCleanup
    )
    Write-SectionHeader 'Image: cleanup and save' -Accent Yellow -RuleColor Grey -DimLine 'Component cleanup and save can take several minutes; the bar below is normal.'
    # WinSxS component cleanup only pays off when we then recompress hard for a lean
    # release ISO. Fast/None are test-quality builds: skip the multi-minute cleanup.
    # Serviced-WIM cache hits already ran Max cleanup when the entry was published.
    if ($SkipComponentCleanup) {
        Set-WinMintManifestComponentCleanupFact -ComponentCleanup 'SkippedCacheHit'
        LogVerbose "Skipping DISM component cleanup (serviced-WIM cache hit; prior $ImageCompression publish already cleaned)."
    }
    elseif ($ImageCompression -eq 'Max') {
        Invoke-Action 'Running DISM component cleanup on the mounted Windows image' -SpectreProgressIndeterminate {
            LogVerbose "Mount: $MountDir"
            Set-WinMintManifestComponentCleanupFact
            Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Cleanup-Image', '/StartComponentCleanup') | Out-Null
            LogOK 'DISM component cleanup finished.'
        }
    }
    else {
        Set-WinMintManifestComponentCleanupFact -ComponentCleanup 'Skipped'
        LogVerbose "Skipping DISM component cleanup (test-quality image; $ImageCompression compression)."
    }
    Invoke-Action 'Saving and dismounting the Windows image (commit can take several minutes)' -SpectreProgressIndeterminate {
        LogVerbose "Mount: $MountDir"
        Save-WinMintImageMount -MountDir $MountDir
        LogOK 'Windows image saved and dismounted.'
    }
}

function Export-SingleEdition {
    param(
        [ValidateNotNullOrEmpty()][string]$LocalWim,
        [int]$SelectedWimIndex,
        [ValidateNotNullOrEmpty()][string]$SelectedEdition,
        [ValidateSet('Max', 'Fast', 'None')][string]$ImageCompression = 'Max'
    )
    Write-SectionHeader "Image: export $SelectedEdition"
    Invoke-Action "Exporting a single-edition install.wim ($SelectedEdition, $ImageCompression compression)" {
        LogVerbose "Source WIM: $LocalWim | index $SelectedWimIndex | compression $ImageCompression"
        Set-WinMintManifestExportCompressionFact -Compression $ImageCompression
        $exportWim = Join-Path (Split-Path $LocalWim -Parent) 'install_export.wim'
        $null = Export-WindowsImage -SourceImagePath $LocalWim -SourceIndex $SelectedWimIndex -DestinationImagePath $exportWim -CompressionType $ImageCompression -ErrorAction Stop
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
        LogVerbose 'ISO boot layout: UEFI only (expected for ARM64 media).'
        LogVerbose "oscdimg -bootdata: $efiBootName only (no legacy BIOS sector on ARM64)."
        $efiTok = Resolve-OscdimgBootdataFilePath -LiteralPath $efisys
        return ('1#pEF,e,b{0}' -f $efiTok)
    }
    $etfs = Join-Path $IsoContentsRoot 'boot\etfsboot.com'
    $efiTok = Resolve-OscdimgBootdataFilePath -LiteralPath $efisys
    if (Test-Path -LiteralPath $etfs) {
        LogVerbose 'ISO boot layout: legacy BIOS + UEFI (El Torito + EFI boot).'
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

