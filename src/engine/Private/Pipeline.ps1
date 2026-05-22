#Requires -Version 7.3

function Convert-WinMintInstallEsdToWim {
    param(
        [Parameter(Mandatory)][string]$IsoContentsRoot,
        [switch]$DryRun
    )

    $sources = Join-Path $IsoContentsRoot 'sources'
    $wim = Join-Path $sources 'install.wim'
    if (Test-Path -LiteralPath $wim) { return $wim }
    $esd = Join-Path $sources 'install.esd'
    if (-not (Test-Path -LiteralPath $esd)) {
        $uup = Join-Path $sources 'uup'
        if (Test-Path -LiteralPath $uup) {
            throw "This ISO uses a UUP source layout under sources\uup. This builder currently requires sources\install.wim or sources\install.esd; convert the UUP payload to a WIM/ESD ISO before building."
        }
        throw "Neither install.wim nor install.esd was found under $sources."
    }

    Log 'Converting install.esd to install.wim in the staged copy for DISM servicing.'
    if ($DryRun) { LogVerbose 'Dry run still converts the temporary staged ESD so WIM metadata validation is complete.' }
    $images = @(Get-WindowsImage -ImagePath $esd -ErrorAction Stop | Sort-Object ImageIndex)
    foreach ($image in $images) {
        $arguments = @(
            '/English',
            '/Export-Image',
            "/SourceImageFile:`"$esd`"",
            "/SourceIndex:$($image.ImageIndex)",
            "/DestinationImageFile:`"$wim`"",
            '/Compress:max',
            '/CheckIntegrity'
        )
        Invoke-DismExe -Arguments $arguments | Out-Null
    }
    Remove-Item -LiteralPath $esd -Force
    return $wim
}

function Mount-WinMintIsoToWorkTree {
    param(
        [Parameter(Mandatory)][string]$SourceIso,
        [Parameter(Mandatory)][string]$IsoContents,
        [switch]$DryRun
    )

    $resolvedSourceIso = (Resolve-Path -LiteralPath $SourceIso -ErrorAction Stop).Path
    [object[]]$autoPlayState = @(Push-Win11IsoAutoPlaySuppression)
    try {
        if ($DryRun) { Log 'Mounting source ISO for dry-run staging.' } else { Log 'Mounting source ISO.' }
        # Use a drive letter for build staging so Invoke-RobocopyChecked can use
        # robocopy. Copy-Item from a no-drive-letter volume GUID is much slower
        # and can appear hung on large UUP-generated ISOs.
        $iso = Mount-DiskImage -ImagePath $resolvedSourceIso -Access ReadOnly -PassThru -ErrorAction Stop
        $volume = $iso | Get-Volume -ErrorAction Stop | Select-Object -First 1
        if (-not $volume) { throw 'Mounted ISO did not expose a readable volume.' }
        $root = if ($volume.DriveLetter) {
            "$($volume.DriveLetter):\"
        }
        elseif ($volume.Path) {
            $volume.Path
        }
        else {
            throw 'Mounted ISO did not expose a drive letter or volume path.'
        }
        LogVerbose "Mounted ISO root: $root"
        Invoke-RobocopyChecked -Source $root -Dest $IsoContents
        # Files copied from a read-only ISO inherit FILE_ATTRIBUTE_READONLY. DISM's
        # Mount-WindowsImage checks the WIM's file attributes before validating the
        # process token and throws "You do not have permissions to mount and modify
        # this image" on a read-only WIM — regardless of admin elevation. Clear the
        # attribute recursively on the staged tree so DISM and the rest of the
        # pipeline (autounattend write, setup script staging) can modify files.
        if (-not $DryRun) {
            Clear-WinMintReadOnlyAttribute -Path $IsoContents
        }
    }
    finally {
        Pop-Win11IsoAutoPlaySuppression -State $autoPlayState
    }
}

function Get-WinMintSelectedInstallImage {
    param(
        [Parameter(Mandatory)][string]$InstallWim,
        [Parameter(Mandatory)][string]$EditionName
    )

    $images = @(Get-WindowsImage -ImagePath $InstallWim -ErrorAction Stop | Sort-Object ImageIndex)
    if ($images.Count -eq 0) { throw "No install images found in $InstallWim." }
    $selected = $images | Where-Object { $_.ImageName -eq $EditionName } | Select-Object -First 1
    if (-not $selected) {
        $selected = $images | Where-Object { $_.ImageName -like "*$EditionName*" } | Select-Object -First 1
    }
    if (-not $selected) {
        $available = ($images | ForEach-Object { $_.ImageName }) -join ', '
        throw "Edition '$EditionName' was not found in install.wim. Available editions: $available"
    }
    return $selected
}

function Get-WinMintInstallImagesForBuild {
    param(
        [Parameter(Mandatory)][string]$InstallWim,
        [ValidateSet('TargetLicense', 'Fixed')][string]$EditionMode = 'TargetLicense',
        [string]$EditionName = ''
    )

    $images = @(Get-WindowsImage -ImagePath $InstallWim -ErrorAction Stop | Sort-Object ImageIndex)
    if ($images.Count -eq 0) { throw "No install images found in $InstallWim." }
    if ($EditionMode -eq 'Fixed') {
        if ([string]::IsNullOrWhiteSpace($EditionName)) {
            throw 'Fixed edition mode requires an edition name.'
        }
        return @(Get-WinMintSelectedInstallImage -InstallWim $InstallWim -EditionName $EditionName)
    }

    LogVerbose "Available editions: $(@($images | ForEach-Object { $_.ImageName }) -join ', ')"
    return $images
}

function New-WinMintIsoImage {
    param(
        [Parameter(Mandatory)][string]$IsoContents,
        [Parameter(Mandatory)][string]$ImageArch,
        [Parameter(Mandatory)][string]$OutputIso
    )

    Write-SectionHeader 'Output ISO'
    Invoke-Action "Creating bootable ISO: $OutputIso" {
        $oscdimg = Resolve-OscdimgPath
        $bootData = Get-OscdimgBootDataValue -IsoContentsRoot $IsoContents -ImageArch $ImageArch

        # Defense-in-depth: confirm the architecture-specific UEFI loader is
        # actually present in the staged tree before oscdimg builds the ISO.
        # oscdimg sets the boot sector based on $ImageArch, but if the source
        # ISO was mislabeled (e.g., x64 ISO mistaken for ARM64) the resulting
        # ISO won't boot the target firmware and the user only finds out at
        # install time.
        $efiLoader = switch ($ImageArch) {
            'arm64' { 'efi\boot\bootaa64.efi' }
            'amd64' { 'efi\boot\bootx64.efi' }
            default { $null }
        }
        if ($efiLoader) {
            $efiLoaderPath = Join-Path $IsoContents $efiLoader
            if (-not (Test-Path -LiteralPath $efiLoaderPath)) {
                throw ("$ImageArch ISO build requires '$efiLoader' in the source ISO. " +
                       "The staged tree at '$IsoContents' is missing this file — " +
                       'the source ISO may not be a real ' + $ImageArch + ' Windows installer.')
            }
            LogVerbose "EFI loader present for $ImageArch`: $efiLoaderPath"
        }

        $arguments = @(
            '-m',
            '-o',
            '-u2',
            '-udfver102',
            "-bootdata:$bootData",
            "-l$script:Win11IsoVolumeLabel",
            $IsoContents,
            $OutputIso
        )
        $oldPref = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
        try {
            Log 'oscdimg assembling final ISO (3-5 minutes for a 5 GB ISO; output is suppressed and the bar will appear stuck)…'
            $out = & $oscdimg @arguments 2>&1
            $code = $LASTEXITCODE
            if ($code -ne 0) { throw "oscdimg failed with exit code $code.`n$($out | Out-String)" }
        }
        finally {
            $PSNativeCommandUseErrorActionPreference = $oldPref
        }
        LogOK "ISO written: $OutputIso"
    }
}

function Invoke-WinMintIsoPipeline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$BuildConfig,
        [switch]$DryRun,
        [switch]$ExportHostDrivers,
        [switch]$NoServicedWimCache,
        [string]$PostBuildUsbDriveLetter
    )

    $script:DryRun = [bool]$DryRun
    $script:ExportHostDrivers = [bool]$ExportHostDrivers
    $root = Get-WinMintRepositoryRoot
    $workDir = Join-Path (Get-Win11IsoProcessTempPath) ('WinMint_ISO_' + [Guid]::NewGuid().ToString('n'))
    $isoContents = Join-Path $workDir 'iso'
    $mountDir = Join-Path $workDir 'mount'
    $outputIso = Join-Path (Get-WinMintOutputDirectory) ('WinMint-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.iso')
    $mountedImage = $false

    try {
        # Create $workDir first and stamp the restricted ACL on it BEFORE any
        # children exist. New children inherit the ACL — if we created iso\ and
        # mount\ first, they'd keep the loose %TEMP% ACL (Users:Read), exposing
        # the staged WIM (which contains the autounattend with the password
        # before SetupComplete cleanup) to non-admin users on the build host.
        $null = New-Item -ItemType Directory -Path $workDir -Force
        Protect-WorkDirectory -Path $workDir
        $null = New-Item -ItemType Directory -Path $isoContents, $mountDir -Force
        if (Get-Command Write-WinMintHeadlessWorkMarker -ErrorAction SilentlyContinue) {
            Write-WinMintHeadlessWorkMarker -WorkDir $workDir -MountDir $mountDir -IsoContents $isoContents
        }
        if (Get-Command Set-WinMintHeadlessJournalPhase -ErrorAction SilentlyContinue) {
            Set-WinMintHeadlessJournalPhase -Phase 'StageIso' -WorkDir $workDir -MountDir $mountDir -IsoContents $isoContents
        }
        Start-PipelinePhase 'Stage ISO'
        $usedStageCache = $false
        $stageCacheDir = Get-WinMintIsoStageCacheHit -SourceIsoPath $BuildConfig.SourceIso
        if ($null -ne $stageCacheDir) {
            $usedStageCache = $true
            if ($DryRun) {
                Log 'Restoring staged ISO from temp cache for dry-run validation…'
            }
            else {
                Log 'Restoring staged ISO from temp cache (skipping ISO mount and ESD→WIM conversion)…'
            }
            Invoke-RobocopyChecked -Source $stageCacheDir -Dest $isoContents -UserFacingMessage 'Copying cached staged ISO into the working folder (~5 GB; robocopy runs silently)…'
            if (-not $DryRun) { Clear-WinMintReadOnlyAttribute -Path $isoContents }
        }
        else {
            Mount-WinMintIsoToWorkTree -SourceIso $BuildConfig.SourceIso -IsoContents $isoContents -DryRun:$DryRun
            $null = Convert-WinMintInstallEsdToWim -IsoContentsRoot $isoContents -DryRun:$DryRun
        }
        $installWim = Join-Path $isoContents 'sources\install.wim'
        if ($null -ne $script:WinMintBuildManifest) {
            if (Test-Path -LiteralPath $BuildConfig.SourceIso) {
                $script:WinMintBuildManifest.sizeDelta.sourceIsoBytes = (Get-Item -LiteralPath $BuildConfig.SourceIso).Length
            }
            if (Test-Path -LiteralPath $installWim) {
                $script:WinMintBuildManifest.sizeDelta.installWimBeforeServicingBytes = (Get-Item -LiteralPath $installWim).Length
            }
        }
        $readiness = Test-OfflineStagingReadiness `
            -LocalInstallWim $installWim `
            -IsoContentsRoot $isoContents `
            -ExpectedArchHint $BuildConfig.Architecture `
            -ScriptDirForChecks $root `
            -DriverSource ([string]$BuildConfig.Drivers.Source) `
            -CustomDriverPath ([string]$BuildConfig.Drivers.Path) `
            -ExportHostDrivers ([bool]$ExportHostDrivers)
        $imageArch = $readiness.Architecture
        Test-RemoteBuildPrerequisite `
            -TargetArch $imageArch `
            -IsoContentsRoot $isoContents `
            -AutounattendPath (Get-WinMintPath -Name Config -ChildPath 'autounattend.xml') `
            -ExportHostDriversRequested:$ExportHostDrivers
        Complete-PipelinePhase 'Stage ISO'
        if (-not $DryRun -and -not $usedStageCache) {
            Publish-WinMintIsoStageCache -SourceIsoPath $BuildConfig.SourceIso -IsoContentsPath $isoContents
        }

        $editionMode = if ([string]::IsNullOrWhiteSpace([string]$BuildConfig.EditionMode)) { 'TargetLicense' } else { [string]$BuildConfig.EditionMode }
        if ($editionMode -notin @('TargetLicense', 'Fixed')) { $editionMode = 'TargetLicense' }
        $installImages = @(Get-WinMintInstallImagesForBuild -InstallWim $installWim -EditionMode $editionMode -EditionName $BuildConfig.Edition)
        if ($editionMode -eq 'TargetLicense') {
            Log "Edition mode: target license. Servicing $($installImages.Count) install image(s) so Windows Setup can choose the target device edition."
            if ($installImages.Count -gt 1) {
                Log "Build-time note: selecting a fixed Home/Pro edition services one image and skips the other edition passes."
            }
        } else {
            $fixedEdition = [string]$BuildConfig.Edition
            if ([string]::IsNullOrWhiteSpace($fixedEdition)) { $fixedEdition = 'selected edition' }
            Log "Edition mode: fixed. Servicing only '$fixedEdition'."
        }

        # Defensive: Get-WindowsImage in some PS7+DISM compat-session combos returns
        # objects whose ImageName lookup fails under StrictMode v2. Fall back to the
        # alternative property names DISM uses, and finally to a dism.exe re-query.
        function Get-WimImageName { param($img)
            foreach ($prop in 'ImageName', 'Name', 'WimImageName') {
                if ($img.PSObject.Properties.Name -contains $prop) {
                    $val = [string]$img.$prop
                    if (-not [string]::IsNullOrWhiteSpace($val)) { return $val }
                }
            }
            return ''
        }

        if ($null -ne $script:WinMintBuildManifest) {
            $editionNames = @($installImages | ForEach-Object { Get-WimImageName -img $_ } | Where-Object { $_ })
            if ($editionNames.Count -lt $installImages.Count) {
                $firstImagePropertyNames = (@($installImages)[0].PSObject.Properties.Name) -join ', '
                LogWarn "Get-WindowsImage returned $($installImages.Count) image(s) but only $($editionNames.Count) had a readable ImageName. Properties on first object: $firstImagePropertyNames"
            }
            $script:WinMintBuildManifest.source.editions = $editionNames
        }

        if ($DryRun) {
            $dryRunImage = $installImages | Select-Object -First 1
            $setupProfile = New-WinMintSetupProfile -BuildConfig $BuildConfig
            $agentProfile = New-WinMintAgentProfile -BuildConfig $BuildConfig
            $setupPlan = New-WinMintSetupPlan -BuildConfig $BuildConfig -SetupProfile $setupProfile -AgentProfile $agentProfile
            $preparedSetup = Install-Autounattend `
                -MountDir $mountDir `
                -IsoContents $isoContents `
                -AutounattendTemplate (Get-Content -LiteralPath (Get-WinMintPath -Name Config -ChildPath 'autounattend.xml') -Raw) `
                -ImageArch $imageArch `
                -TimeZone $BuildConfig.TimeZoneId `
                -TargetPCName $BuildConfig.ComputerName `
                -TargetUser $BuildConfig.AccountName `
                -AccountMode $BuildConfig.AccountMode `
                -TargetPass $BuildConfig.Password `
                -EditionName $dryRunImage.ImageName `
                -EditionMode $editionMode `
                -AutoWipeDisk:$BuildConfig.AutoWipeDisk `
                -AutoLogon:$BuildConfig.AutoLogon `
                -DiskLayout $BuildConfig.DiskLayout `
                -HardwareBypass:$BuildConfig.Tweaks.HardwareBypass `
                -InputLocale $BuildConfig.InputLocale `
                -SystemLocale $BuildConfig.SystemLocale `
                -UILanguage $BuildConfig.UILanguage `
                -UILanguageFallback $BuildConfig.UILanguageFallback `
                -UserLocale $BuildConfig.SetupUserLocale `
                -ScriptRoot $root `
                -AgentProfile $agentProfile `
                -SetupProfile $setupProfile `
                -SetupPlan $setupPlan `
                -DryRun
            $dryRunArtifacts = Save-WinMintDryRunArtifacts `
                -Config $BuildConfig `
                -DetectedArchitecture $imageArch `
                -InstallImages $installImages `
                -PreparedSetup $preparedSetup `
                -WorkDir $workDir `
                -IsoContents $isoContents `
                -InstallWim $installWim
            Write-WinMintDryRunArtifactSummary -Artifacts $dryRunArtifacts
            LogOK 'Dry run completed. No WIM customization, output ISO, disk prep, or USB write was performed.'
            return [pscustomobject]@{ OutputIsoPath = $null; WorkDir = $workDir; DryRun = $true; DryRunArtifacts = $dryRunArtifacts }
        }

        # Probe the serviced-install.wim cache before any expensive servicing work.
        # On hit we restore the cached wim over the freshly-staged one and skip the
        # 30-60 min DISM mount/inject/dismount loop. Per-image mount still happens
        # so autounattend/setup scripts can be re-stamped per build.
        $servicedWimCacheHit = $null
        $servicedWimFingerprint = $null
        if (-not $NoServicedWimCache) {
            try {
                $isoStageKey = Get-WinMintIsoStageCacheKeyHex -Fingerprint (Get-WinMintIsoStageCacheFingerprint -SourceIsoPath $BuildConfig.SourceIso)
                $servicedWimFingerprint = Get-WinMintServicedWimFingerprint -BuildConfig $BuildConfig -IsoStageKey $isoStageKey
                $servicedWimCacheHit = Get-WinMintServicedWimCacheHit -Fingerprint $servicedWimFingerprint
            }
            catch {
                LogVerbose "Serviced WIM cache probe skipped: $($_.Exception.Message)"
                $servicedWimCacheHit = $null
            }
        }
        if ($null -ne $servicedWimCacheHit) {
            Log "Restoring serviced install.wim from temp cache (skipping driver injection, appx removal, and package install)…"
            Copy-Item -LiteralPath $servicedWimCacheHit -Destination $installWim -Force -ErrorAction Stop
            if ($null -ne $script:WinMintBuildManifest) {
                $script:WinMintBuildManifest | Add-Member -NotePropertyName servicedWimCacheRestored -NotePropertyValue $true -Force
            }
        }

        Sync-NerdFont -FontDir (Join-Path $root 'assets\runtime\fonts')
        Sync-Cursor -CursorsDir (Join-Path $root 'assets\runtime\cursors') -PackKind $BuildConfig.CursorPackKind

        $driverSources = [System.Collections.Generic.List[object]]::new()
        if ($null -eq $servicedWimCacheHit) {
            if ($BuildConfig.Drivers.Source -eq 'Custom') {
                $customDrivers = Resolve-Win11IsoCustomDriverSource -Path $BuildConfig.Drivers.Path -WorkDir $workDir
                if ($customDrivers -and $customDrivers.Ready) {
                    $driverSources.Add([pscustomobject]@{ Source = $customDrivers.Source; Label = $customDrivers.Label })
                }
            }
            if ($ExportHostDrivers) {
                $hostDriverDir = Join-Path $workDir 'host_drivers'
                $hostDriverCache = Get-WinMintHostDriverExportCacheHit
                if ($null -ne $hostDriverCache) {
                    Log 'Restoring exported host drivers from temp cache (skipping Export-WindowsDriver)…'
                    $null = New-Item -ItemType Directory -Path $hostDriverDir -Force
                    Invoke-RobocopyChecked -Source $hostDriverCache -Dest $hostDriverDir -UserFacingMessage 'Copying cached host driver export into the work folder…'
                    Clear-WinMintReadOnlyAttribute -Path $hostDriverDir
                }
                else {
                    Invoke-Action 'Exporting host drivers for injection' {
                        Export-WinMintHostDrivers -Destination $hostDriverDir | Out-Null
                    }
                    Publish-WinMintHostDriverExportCache -SourceDir $hostDriverDir
                }
                $driverSources.Add([pscustomobject]@{ Source = $hostDriverDir; Label = 'Host export' })
            }
        }

        Start-PipelinePhase 'Service WIM'
        if (Get-Command Set-WinMintHeadlessJournalPhase -ErrorAction SilentlyContinue) {
            Set-WinMintHeadlessJournalPhase -Phase 'ServiceWim' -WorkDir $workDir -MountDir $mountDir -IsoContents $isoContents
        }
        $firstServicedImage = $true
        $imageOrdinal = 0
        $imageTotal = @($installImages).Count
        foreach ($image in $installImages) {
            $imageOrdinal++
            $imgName = Get-WimImageName -img $image
            if ([string]::IsNullOrWhiteSpace($imgName)) { $imgName = "index $($image.ImageIndex)" }
            Write-SectionHeader "Image ${imageOrdinal}/${imageTotal}: service $imgName"
            Log "Mounting install.wim index $($image.ImageIndex) ($imgName)… image $imageOrdinal of $imageTotal."
            $mountTimer = [System.Diagnostics.Stopwatch]::StartNew()
            $null = Mount-WindowsImage -ImagePath $installWim -Index $image.ImageIndex -Path $mountDir -ErrorAction Stop
            $mountTimer.Stop()
            LogOK "install.wim index $($image.ImageIndex) mounted in $(Format-WinMintDuration -Duration $mountTimer.Elapsed); proceeding to servicing."
            $mountedImage = $true
            $setupProfile = New-WinMintSetupProfile -BuildConfig $BuildConfig
            $agentProfile = New-WinMintAgentProfile -BuildConfig $BuildConfig
            $setupPlan = New-WinMintSetupPlan -BuildConfig $BuildConfig -SetupProfile $setupProfile -AgentProfile $agentProfile
            Install-Autounattend `
                -MountDir $mountDir `
                -IsoContents $isoContents `
                -AutounattendTemplate (Get-Content -LiteralPath (Get-WinMintPath -Name Config -ChildPath 'autounattend.xml') -Raw) `
                -ImageArch $imageArch `
                -TimeZone $BuildConfig.TimeZoneId `
                -TargetPCName $BuildConfig.ComputerName `
                -TargetUser $BuildConfig.AccountName `
                -AccountMode $BuildConfig.AccountMode `
                -TargetPass $BuildConfig.Password `
                -EditionName $imgName `
                -EditionMode $editionMode `
                -AutoWipeDisk:$BuildConfig.AutoWipeDisk `
                -AutoLogon:$BuildConfig.AutoLogon `
                -DiskLayout $BuildConfig.DiskLayout `
                -HardwareBypass:$BuildConfig.Tweaks.HardwareBypass `
                -InputLocale $BuildConfig.InputLocale `
                -SystemLocale $BuildConfig.SystemLocale `
                -UILanguage $BuildConfig.UILanguage `
                -UILanguageFallback $BuildConfig.UILanguageFallback `
                -UserLocale $BuildConfig.SetupUserLocale `
                -ScriptRoot $root `
                -AgentProfile $agentProfile `
                -SetupProfile $setupProfile `
                -SetupPlan $setupPlan

            if ($null -eq $servicedWimCacheHit) {
                Invoke-AppxRemoval -MountDir $mountDir -PackagePrefixes $BuildConfig.AppxPackages
                Remove-WinMintCapabilities -MountDir $mountDir
                Remove-NonEnglishLanguageFeature `
                    -MountDir $mountDir `
                    -PreserveLanguages @($BuildConfig.UILanguage, $BuildConfig.UILanguageFallback, $BuildConfig.SystemLocale, $BuildConfig.UserLocale, $BuildConfig.SetupUserLocale) `
                    -Confirm:$false
                Invoke-RegistryTweak -MountDir $mountDir -GroupIds $BuildConfig.RegistryTweaks
                Remove-WinMintOneDriveSetupStub -MountDir $mountDir
                Enable-WinMintOptionalFeature -MountDir $mountDir -Features $BuildConfig.Features
                Install-OfflinePowerShell7 -MountDir $mountDir -TargetArch $imageArch
                Install-OfflineViveTool -MountDir $mountDir -TargetArch $imageArch
                Install-OfflineFont -MountDir $mountDir -ScriptDir $root
                Install-OfflineCursor -MountDir $mountDir -ScriptDir $root -CursorPackKind $BuildConfig.CursorPackKind
                Install-OfflineWinget -MountDir $mountDir

                foreach ($driverSource in $driverSources) {
                    Invoke-DriverInjection `
                        -MountDir $mountDir `
                        -IsoContents $isoContents `
                        -DriverSource $driverSource.Source `
                        -SourceLabel $driverSource.Label `
                        -InjectWinPE:$firstServicedImage
                }
            }
            else {
                Log "Serviced WIM cache hit: skipping appx removal, package install, and driver injection for image $imgName."
            }

            Save-ImageWithCleanup -MountDir $mountDir
            $mountedImage = $false
            $firstServicedImage = $false
        }
        Complete-PipelinePhase 'Service WIM'
        if ($null -ne $script:WinMintBuildManifest -and (Test-Path -LiteralPath $installWim)) {
            $script:WinMintBuildManifest.sizeDelta.installWimAfterServicingBytes = (Get-Item -LiteralPath $installWim).Length
        }
        if (-not $NoServicedWimCache -and $null -eq $servicedWimCacheHit -and -not [string]::IsNullOrWhiteSpace($servicedWimFingerprint) -and (Test-Path -LiteralPath $installWim)) {
            Publish-WinMintServicedWimCache -Fingerprint $servicedWimFingerprint -ServicedWimPath $installWim
        }

        if ($null -ne $script:WinMintBuildManifest) {
            $infNames = @(
                foreach ($ds in $driverSources) {
                    if ($ds.Source -and (Test-Path -LiteralPath $ds.Source)) {
                        Get-ChildItem -LiteralPath $ds.Source -Recurse -Filter '*.inf' -ErrorAction SilentlyContinue |
                            Select-Object -ExpandProperty Name
                    }
                }
            )
            $script:WinMintBuildManifest.drivers.injectedCount = $infNames.Count
            $script:WinMintBuildManifest.drivers.infNames = @($infNames | Sort-Object -Unique)
        }

        Install-WinPEUtility -IsoContents $isoContents -AutoWipeDisk:$BuildConfig.AutoWipeDisk
        if ($editionMode -eq 'Fixed') {
            $selectedImage = $installImages | Select-Object -First 1
            Export-SingleEdition -LocalWim $installWim -SelectedWimIndex $selectedImage.ImageIndex -SelectedEdition $selectedImage.ImageName
        }
        if ($null -ne $script:WinMintBuildManifest -and (Test-Path -LiteralPath $installWim)) {
            $script:WinMintBuildManifest.sizeDelta.installWimAfterExportBytes = (Get-Item -LiteralPath $installWim).Length
        }
        Start-PipelinePhase 'Assemble ISO'
        if (Get-Command Set-WinMintHeadlessJournalPhase -ErrorAction SilentlyContinue) {
            Set-WinMintHeadlessJournalPhase -Phase 'AssembleIso' -WorkDir $workDir -MountDir $mountDir -IsoContents $isoContents
        }
        New-WinMintIsoImage -IsoContents $isoContents -ImageArch $imageArch -OutputIso $outputIso
        if (Test-Path -LiteralPath $outputIso) {
            $isoItem = Get-Item -LiteralPath $outputIso
            $isoHash = (Get-FileHash -LiteralPath $outputIso -Algorithm SHA256).Hash
            if ($null -ne $script:WinMintBuildManifest) {
                $script:WinMintBuildManifest.sizeDelta.outputIsoBytes = $isoItem.Length
                $sourceBytes = $script:WinMintBuildManifest.sizeDelta.sourceIsoBytes
                if ([long]$sourceBytes -gt 0) {
                    $script:WinMintBuildManifest.sizeDelta.outputMinusSourceBytes = [long]$isoItem.Length - [long]$sourceBytes
                    $script:WinMintBuildManifest.sizeDelta.outputToSourceRatio = [math]::Round(([double]$isoItem.Length / [double]$sourceBytes), 4)
                }
            }
            LogOK "Final ISO: $outputIso"
            LogOK "Final ISO size: $(Format-WinMintByteSize -Bytes $isoItem.Length) ($($isoItem.Length) bytes)."
            LogOK "Final ISO SHA256: $isoHash"
        }
        Complete-PipelinePhase 'Assemble ISO'
        if (-not [string]::IsNullOrWhiteSpace($PostBuildUsbDriveLetter)) {
            Invoke-FlashWindowsInstallMediaToUsb -IsoPath $outputIso -SourceRemovableDriveLetter $PostBuildUsbDriveLetter -SkipTypedDestructiveAck
        }
        return [pscustomobject]@{ OutputIsoPath = $outputIso; WorkDir = $workDir; DryRun = $false }
    }
    catch {
        if ($mountedImage) {
            try { Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null }
            catch { Write-Verbose "Discard mounted image after failure: $($_.Exception.Message)" }
        }
        throw
    }
    finally {
        if (Get-Command Set-WinMintHeadlessJournalPhase -ErrorAction SilentlyContinue) {
            Set-WinMintHeadlessJournalPhase -Phase 'Cleanup' -WorkDir $workDir -MountDir $mountDir -IsoContents $isoContents
        }
        Invoke-Cleanup -MountDir $mountDir -SourceIso $BuildConfig.SourceIso -WorkDir $workDir
    }
}
