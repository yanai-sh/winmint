#Requires -Version 7.3

function New-WinMintBuildConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$BuildProfile
    )

    Assert-WinMintBuildProfile -BuildProfile $BuildProfile

    $packages = Get-WinMintPath -Name Config -ChildPath 'packages.json'
    $source = Get-WinMintProfileSetting $BuildProfile 'source' @{}
    $target = Get-WinMintProfileSetting $BuildProfile 'target' @{}
    $identity = Get-WinMintProfileSetting $BuildProfile 'identity' @{}
    $regional = Get-WinMintProfileSetting $BuildProfile 'regional' @{}
    $drivers = Get-WinMintProfileSetting $BuildProfile 'drivers' @{}
    $desktop = Get-WinMintProfileSetting $BuildProfile 'desktop' @{}
    $development = Get-WinMintProfileSetting $BuildProfile 'development' @{}
    $featureToggles = Get-WinMintProfileSetting $BuildProfile 'features' @{}
    $wsl = Get-WinMintProfileSetting $development 'wsl' @{}
    $removals = Get-WinMintProfileSetting $BuildProfile 'removals' @{}
    $privacy = Get-WinMintProfileSetting $BuildProfile 'privacy' @{}
    $tweaks = Get-WinMintProfileSetting $BuildProfile 'tweaks' @{}

    $profileName = [string](Get-WinMintProfileSetting $BuildProfile 'profileName' 'Developer')
    $setupOption = [string](Get-WinMintProfileSetting $BuildProfile 'setupOption' 'Minimal')
    if ($setupOption -notin @('Minimal', 'CopilotPlus')) { $setupOption = 'Minimal' }
    $profileGroups = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $BuildProfile 'profileGroups' @()))
    if ($profileGroups.Count -eq 0) {
        $profileGroups = if ($setupOption -eq 'CopilotPlus') { @('Minimal', 'CopilotPlus') } else { @('Minimal') }
    }
    $enableDeveloperGroup = $profileGroups -contains 'Developer'
    $selectedEditors = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $development 'editors' @()))
    $driverSource = [string](Get-WinMintProfileSetting $drivers 'source' 'None')
    $driverPath = [string](Get-WinMintProfileSetting $drivers 'path' '')
    $exportHostDrivers = ($driverSource -eq 'Host')
    $wsl2Distros = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $wsl 'distros' @()))
    $enableWsl = [bool](Get-WinMintProfileSetting $wsl 'enabled' ($wsl2Distros.Count -gt 0)) -or $wsl2Distros.Count -gt 0
    $wsl2Distro = if ($wsl2Distros.Count -eq 0) { 'None' } elseif ($wsl2Distros.Count -eq 1) { $wsl2Distros[0] } else { $wsl2Distros -join ',' }
    $layers = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $desktop 'layers' @()))
    $launcher = [string](Get-WinMintProfileSetting $featureToggles 'launcher' '')
    if ([string]::IsNullOrWhiteSpace($launcher)) {
        $launcher = if ([bool](Get-WinMintProfileSetting $featureToggles 'flowEverything' $false)) { 'FlowEverything' } else { 'None' }
    }
    if ($launcher -notin @('None', 'FlowEverything', 'Raycast')) { $launcher = 'None' }
    $installFlowEverything = ($launcher -eq 'FlowEverything')
    $installRaycast = ($launcher -eq 'Raycast')
    $enableLiveInstallAudit = [bool](Get-WinMintProfileSetting $featureToggles 'liveInstallAudit' $false)
    $enablePhoneLink = [bool](Get-WinMintProfileSetting $featureToggles 'phoneLink' $false)
    $password = if ([bool](Get-WinMintProfileSetting $identity 'passwordIncluded' $false)) {
        [string](Get-WinMintProfileSetting $identity 'password' '')
    } else {
        ''
    }
    $accountMode = [string](Get-WinMintProfileSetting $identity 'accountMode' 'Local')
    if ($accountMode -notin @('Local', 'MicrosoftOobe')) { $accountMode = 'Local' }
    $passwordSet = [bool](Get-WinMintProfileSetting $identity 'passwordSet' $false)
    $passwordIncluded = [bool](Get-WinMintProfileSetting $identity 'passwordIncluded' $false)
    $diskMode = [string](Get-WinMintProfileSetting $target 'diskMode' 'Manual')
    if ($diskMode -notin @('Manual', 'AutoWipeDisk0', 'DualBootReserved')) { $diskMode = 'Manual' }
    $diskLayout = Get-WinMintProfileSetting $target 'diskLayout' $null
    if ($null -eq $diskLayout) {
        $diskLayout = [ordered]@{
            mode = $diskMode
            preset = ''
            roundingGb = 64
            windowsMinimumGb = 256
            windowsRecommendedGb = 384
            linuxMinimumGb = 128
            linuxRecommendedGb = 256
            efiMb = 1024
            msrMb = 16
            recoveryMb = 1024
        }
    }
    $features = [System.Collections.Generic.List[string]]::new()
    if ($enableDeveloperGroup) { $features.Add('OpenSSH.Client') }
    if ($enableWsl) {
        $features.Add('Microsoft-Windows-Subsystem-Linux')
        $features.Add('VirtualMachinePlatform')
    }
    $registryTweaks = [System.Collections.Generic.List[string]]::new()
    $tweakDarkMode = [bool](Get-WinMintProfileSetting $tweaks 'darkMode' $true)
    $tweakFileExtensions = [bool](Get-WinMintProfileSetting $tweaks 'fileExtensions' $true)
    $tweakStickyKeys = [bool](Get-WinMintProfileSetting $tweaks 'stickyKeys' $true)
    $tweakHardwareBypass = [bool](Get-WinMintProfileSetting $tweaks 'hardwareBypass' $false)
    $tweakDmaInterop = [bool](Get-WinMintProfileSetting $tweaks 'dmaInterop' $false)
    $updatePolicy = 'All'
    $privacyTelemetry = [bool](Get-WinMintProfileSetting $privacy 'telemetry' $true)
    $privacyAdvertisingId = [bool](Get-WinMintProfileSetting $privacy 'advertisingId' $true)
    $privacyLocation = [bool](Get-WinMintProfileSetting $privacy 'location' $false)
    $privacyTimeline = [bool](Get-WinMintProfileSetting $privacy 'timeline' $true)
    $aiRemoval = New-WinMintAiRemovalConfig -Removals $removals -SetupOption $setupOption
    $dmaSetupRegion = Resolve-WinMintDmaInteropSetupRegion
    $restoreUserLocale = [string](Get-WinMintProfileSetting $regional 'userLocale' '')
    $restoreHomeLocationGeoId = [int](Get-WinMintProfileSetting $regional 'homeLocationGeoId' (Resolve-WinMintRegionGeoId -CultureName $restoreUserLocale))
    $dmaSetupUserLocale = if ($tweakDmaInterop) { [string]$dmaSetupRegion.Culture } else { $restoreUserLocale }
    $dmaSetupHomeLocationGeoId = if ($tweakDmaInterop) { [int]$dmaSetupRegion.GeoId } else { $restoreHomeLocationGeoId }
    if ($tweakHardwareBypass) {
        $registryTweaks.Add('hardware-bypass')
    }
    if ($tweakFileExtensions) {
        $registryTweaks.Add('developer-qol')
    }
    $registryTweaks.Add('uac-no-secure-desktop')
    $registryTweaks.Add('terminal-admin-context')
    if ($privacyTelemetry -or $privacyAdvertisingId) {
        $registryTweaks.Add('edge-policy-minimal')
    }
    if ([string]$aiRemoval.Policy -eq 'Core') {
        $registryTweaks.Add('windows-ai-core-policy')
    }
    elseif ([string]$aiRemoval.Policy -in @('ServiceableFull', 'AggressiveExperimental')) {
        $registryTweaks.Add('windows-ai-full-policy')
    }
    if ($diskMode -eq 'DualBootReserved') {
        $registryTweaks.Add('dual-boot-windows-policy')
    }
    if ($enableDeveloperGroup) {
        $registryTweaks.Add('developer-mode')
        $registryTweaks.Add('powershell-remotesigned')
    }
    if ([bool](Get-WinMintProfileSetting $removals 'microsoftApps' $true)) {
        $registryTweaks.Add('onedrive-policy')
    }
    if ([bool](Get-WinMintProfileSetting $removals 'gaming' $true)) {
        $registryTweaks.Add('gamebar-policy')
    }
    $profileEffectiveAppx = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $removals 'effectiveAppx' @()))
    $baseAppxRemovalPrefixes = if ($profileEffectiveAppx.Count -gt 0) {
        @($profileEffectiveAppx)
    }
    else {
        @(Get-WinMintProfileAppxRemovalPrefix -Removals $removals)
    }
    $appxRemovalPrefixes = @($baseAppxRemovalPrefixes + @($aiRemoval.AppxPrefixes) | Where-Object { $_ } | Sort-Object -Unique)

    $rawEditionMode = [string](Get-WinMintProfileSetting $target 'editionMode' 'TargetLicense')
    $editionMode = switch -Regex ($rawEditionMode) {
        '^(TargetLicense|Target|License|Auto)$' { 'TargetLicense'; break }
        '^(Fixed|Forced|Force)$' { 'Fixed'; break }
        default { 'TargetLicense' }
    }
    $edition = [string](Get-WinMintProfileSetting $target 'edition' '')
    if ($editionMode -eq 'Fixed' -and [string]::IsNullOrWhiteSpace($edition)) {
        $edition = 'Windows 11 Pro'
    }
    [pscustomobject]@{
        Profile = $profileName
        ProfileGroups = @($profileGroups)
        SetupOption = $setupOption
        SourceIso = [string](Get-WinMintProfileSetting $source 'isoPath' '')
        Architecture = [string](Get-WinMintProfileSetting $source 'architecture' '')
        EditionMode = $editionMode
        Edition = $edition
        TargetDevice = [string](Get-WinMintProfileSetting $target 'device' 'DifferentPC')
        ComputerName = [string](Get-WinMintProfileSetting $identity 'computerName' '')
        AccountName = [string](Get-WinMintProfileSetting $identity 'accountName' '')
        AccountMode = $accountMode
        Password = $password
        PasswordSet = $passwordSet
        PasswordIncluded = $passwordIncluded
        AutoLogon = [bool](Get-WinMintProfileSetting $identity 'autoLogon' $false)
        DiskMode = $diskMode
        DiskLayout = $diskLayout
        AutoWipeDisk = ($diskMode -in @('AutoWipeDisk0', 'DualBootReserved'))
        CursorPackKind = [string](Get-WinMintProfileSetting $desktop 'cursorPack' $script:Win11IsoDefaultCursorPackKind)
        TimeZoneId = [string](Get-WinMintProfileSetting $regional 'timeZoneId' '')
        InputLocale = [string](Get-WinMintProfileSetting $regional 'inputLocale' '')
        SystemLocale = [string](Get-WinMintProfileSetting $regional 'systemLocale' '')
        UILanguage = [string](Get-WinMintProfileSetting $regional 'uiLanguage' '')
        UILanguageFallback = [string](Get-WinMintProfileSetting $regional 'uiLanguageFallback' '')
        UserLocale = $restoreUserLocale
        HomeLocationGeoId = $restoreHomeLocationGeoId
        SetupUserLocale = $dmaSetupUserLocale
        SetupHomeLocationGeoId = $dmaSetupHomeLocationGeoId
        DmaInterop = [pscustomobject]@{
            Enabled = $tweakDmaInterop
            SetupCountry = [string]$dmaSetupRegion.Country
            SetupUserLocale = $dmaSetupUserLocale
            SetupHomeLocationGeoId = $dmaSetupHomeLocationGeoId
            RestoreUserLocale = $restoreUserLocale
            RestoreHomeLocationGeoId = $restoreHomeLocationGeoId
            RestoreLocationServices = $privacyLocation
            Policy = if ($tweakDmaInterop) {
                'Opt-in DMA interoperability uses an EEA setup region, disables automatic time-zone updates, then restores the configured regional defaults after successful FirstLogon.'
            } else {
                'Disabled; setup uses the configured regional defaults.'
            }
        }
        ExportHostDrivers = $exportHostDrivers
        Editors = @($selectedEditors)
        InstallWindhawk = ($layers -contains 'windhawk')
        InstallYasb = ($layers -contains 'yasb')
        InstallKomorebi = ($layers -contains 'komorebi')
        Launcher = $launcher
        InstallFlowEverything = $installFlowEverything
        InstallRaycast = $installRaycast
        LiveInstallAudit = $enableLiveInstallAudit
        PhoneLink = $enablePhoneLink
        Wsl2Distro = $wsl2Distro
        Wsl2Distros = @($wsl2Distros)
        AppxPackages = @($appxRemovalPrefixes)
        AiRemoval = $aiRemoval
        RegistryTweaks = $registryTweaks.ToArray()
        Features = $features.ToArray()
        Tweaks = [pscustomobject]@{
            DarkMode = $tweakDarkMode
            FileExtensions = $tweakFileExtensions
            StickyKeys = $tweakStickyKeys
            HardwareBypass = $tweakHardwareBypass
            DmaInterop = $tweakDmaInterop
            UpdatePolicy = $updatePolicy
        }
        Privacy = [pscustomobject]@{
            Telemetry = $privacyTelemetry
            AdvertisingId = $privacyAdvertisingId
            Location = $privacyLocation
            Timeline = $privacyTimeline
        }
        Drivers = [pscustomobject]@{ Source = $driverSource; Path = $driverPath }
        NoServicedWimCache = [bool](Get-WinMintProfileSetting $BuildProfile 'noServicedWimCache' $false)
        SetupScripts = @('SetupComplete.cmd', 'SetupComplete.ps1', 'Specialize.ps1', 'DefaultUser.ps1', 'FirstLogon.ps1', 'WinMintAgent', 'ViVeTool')
        Assets = @('fonts', 'cursors', 'PowerShell 7', 'winget')
        PackagesManifest = $packages
    }
}

function Get-WinMintPowerShellCachePattern {
    param([string]$Architecture)

    $suffix = switch ($Architecture) {
        'arm64' { 'win-arm64' }
        'x86' { 'win-x86' }
        default { 'win-x64' }
    }
    return "PowerShell-*-$suffix.zip"
}

function Get-WinMintViveToolCachePattern {
    param([string]$Architecture)

    if ($Architecture -eq 'arm64') {
        return @('ViVeTool-*Arm64*.zip', 'ViVeTool-*ARM64*.zip', 'ViVeTool-*arm64*.zip')
    }
    return @('ViVeTool-*IntelAmd*.zip', 'ViVeTool-*.zip')
}

function Get-WinMintOfflinePayloadCacheStatus {
    param(
        [string]$Architecture = 'amd64',
        [string]$DownloadDir = (Join-Path (Get-Win11IsoDependencyCacheRoot) 'downloads'),
        [string]$FontDir = (Join-Path (Get-WinMintRepositoryRoot) 'assets\runtime\fonts')
    )

    $missing = [System.Collections.Generic.List[string]]::new()
    $found = [ordered]@{}

    $ps7 = Get-WinMintCachedDownloadFile -DownloadDir $DownloadDir -Patterns @((Get-WinMintPowerShellCachePattern -Architecture $Architecture))
    if ($ps7) { $found['PowerShell 7'] = $ps7 } else { $missing.Add('PowerShell 7') | Out-Null }

    $vive = Get-WinMintCachedDownloadFile -DownloadDir $DownloadDir -Patterns @(Get-WinMintViveToolCachePattern -Architecture $Architecture)
    if ($vive) { $found['ViVeTool'] = $vive } else { $missing.Add('ViVeTool') | Out-Null }

    $winget = Get-WinMintCachedDownloadFile -DownloadDir $DownloadDir -Patterns @('Microsoft.DesktopAppInstaller_*.msixbundle', '*.msixbundle')
    if ($winget) { $found['winget'] = $winget } else { $missing.Add('winget') | Out-Null }

    $font = if (Test-Path -LiteralPath $FontDir) {
        Get-ChildItem -LiteralPath $FontDir -Filter '*CascadiaCodeNF-Regular.ttf' -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
    } else {
        $null
    }
    if ($font) { $found['Cascadia Code font'] = $font.FullName } else { $missing.Add('Cascadia Code font') | Out-Null }

    [pscustomobject]@{
        Complete = ($missing.Count -eq 0)
        Missing = $missing.ToArray()
        Found = $found
    }
}

function Test-WinMintBuildPrerequisite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [switch]$AllowMissingSourceIso
    )

    $warnings = [System.Collections.Generic.List[string]]::new()
    $failures = [System.Collections.Generic.List[string]]::new()
    $sourceIsoMissing = [string]::IsNullOrWhiteSpace($Config.SourceIso)
    if ($sourceIsoMissing) {
        if ($AllowMissingSourceIso) {
            $warnings.Add('Dry run profile-only mode: no source ISO was provided, so WIM metadata and setup artifacts are skipped.')
        }
        else {
            $failures.Add('Source ISO is not set.')
        }
    }
    elseif (-not (Test-Path -LiteralPath $Config.SourceIso)) { $failures.Add("Source ISO not found: $($Config.SourceIso)") }
    if ([string]::IsNullOrWhiteSpace([string]$Config.Architecture)) {
        $failures.Add('Architecture is not set; oscdimg cannot pick a boot layout without it.')
    }
    if (-not (Test-Path -LiteralPath $Config.PackagesManifest)) { $warnings.Add("Package manifest missing: $($Config.PackagesManifest)") }
    if (-not ($AllowMissingSourceIso -and $sourceIsoMissing) -and -not (Test-WinMintGitHubApiReachable -TimeoutSec 5)) {
        $cache = Get-WinMintOfflinePayloadCacheStatus -Architecture ([string]$Config.Architecture)
        if ($cache.Complete) {
            $warnings.Add('No internet connectivity to api.github.com; cached PowerShell 7, ViVeTool, winget, and Cascadia payloads are present, so the build can continue offline.')
        }
        else {
            $failures.Add("No internet connectivity to api.github.com and offline payload cache is incomplete. Missing: $($cache.Missing -join ', '). Connect and retry once to refresh the cache.")
        }
    }
    if ($Config.PasswordSet -and -not $Config.PasswordIncluded) {
        $failures.Add('The build profile says a password was set, but the password secret is not included. Re-enter the password in the UI before building.')
    }
    if ($Config.AutoLogon -and [string]::IsNullOrWhiteSpace([string]$Config.Password)) {
        $failures.Add('Autologon requires an included account password.')
    }
    if ($Config.Architecture -and $Config.SourceIso) {
        $hint = Get-WinMintIsoArchitectureHint -Path $Config.SourceIso
        if ($hint -and $hint -ne $Config.Architecture) {
            $warnings.Add("ISO filename suggests $hint, but config selected $($Config.Architecture).")
        }
    }
    if ($Config.TargetDevice -eq 'ThisPC' -and $Config.Architecture) {
        $hostArch = Get-BuildHostProcessorArchitecture
        if ($hostArch -ne $Config.Architecture) {
            $failures.Add("This PC target requires the ISO architecture ($($Config.Architecture)) to match this PC ($hostArch). Choose Different PC for cross-machine builds.")
        }
    }
    if ($Config.Drivers.Source -eq 'Host' -and $Config.Architecture) {
        $hostArch = Get-BuildHostProcessorArchitecture
        if ($hostArch -ne $Config.Architecture) {
            $failures.Add("Mirror PC drivers require the build PC architecture ($hostArch) to match the target ISO architecture ($($Config.Architecture)).")
        }
        if (
            -not (Get-Command Export-WindowsDriver -ErrorAction SilentlyContinue) -and
            -not (Get-Command pnputil.exe -CommandType Application -ErrorAction SilentlyContinue)
        ) {
            $failures.Add('Mirror PC drivers were requested, but neither Export-WindowsDriver nor pnputil.exe is available. Install/configure Windows driver export tooling or choose a custom driver pack.')
        }
    }
    if ($Config.InstallWindhawk) {
        $windhawkBootstrap = Get-WinMintPath -Name Setup -ChildPath 'WindhawkBootstrap.ps1'
        $virtualDesktopFlyouts = Get-WinMintPath -Name Setup -ChildPath 'DisableVirtualDesktopFlyouts.ps1'
        $windhawkPreset = Join-Path (Get-WinMintRepositoryRoot) 'assets\runtime\desktop\windhawk\preset.json'
        if (-not (Test-Path -LiteralPath $windhawkBootstrap)) {
            $failures.Add("WinMint Windhawk bootstrap script is missing from the repository: $windhawkBootstrap")
        }
        if (-not (Test-Path -LiteralPath $virtualDesktopFlyouts)) {
            $failures.Add("WinMint virtual desktop flyout script is missing from the repository: $virtualDesktopFlyouts")
        }
        if (-not (Test-Path -LiteralPath $windhawkPreset)) {
            $failures.Add("WinMint Windhawk preset is missing from the repository: $windhawkPreset")
        }
    }
    if ($Config.InstallYasb) {
        foreach ($asset in @('assets\runtime\desktop\yasb\config.yaml', 'assets\runtime\desktop\yasb\styles.css')) {
            $path = Join-Path (Get-WinMintRepositoryRoot) $asset
            if (-not (Test-Path -LiteralPath $path)) {
                $failures.Add("WinMint YASB preset asset is missing from the repository: $path")
            }
        }
    }
    if ($Config.InstallKomorebi) {
        foreach ($asset in @('assets\runtime\desktop\komorebi\komorebi.json', 'assets\runtime\desktop\komorebi\applications.json', 'assets\runtime\desktop\komorebi\whkdrc')) {
            $path = Join-Path (Get-WinMintRepositoryRoot) $asset
            if (-not (Test-Path -LiteralPath $path)) {
                $failures.Add("WinMint Komorebi preset asset is missing from the repository: $path")
            }
        }
    }
    if ($Config.Drivers.Source -eq 'Custom') {
        $driverPath = [string]$Config.Drivers.Path
        if ([string]::IsNullOrWhiteSpace($driverPath)) {
            $failures.Add('Custom driver source was selected, but no driver path was provided.')
        }
        elseif (-not (Test-Path -LiteralPath $driverPath)) {
            $failures.Add("Custom driver path not found: $driverPath")
        }
        else {
            $item = Get-Item -LiteralPath $driverPath
            if (-not $item.PSIsContainer -and $item.Extension -notin '.inf', '.msi', '.zip') {
                $failures.Add("Custom driver path must be a .inf file, .msi file, .zip file, or folder: $driverPath")
            }
        }
    }
    [pscustomobject]@{ Passed = ($failures.Count -eq 0); Warnings = $warnings.ToArray(); Failures = $failures.ToArray() }
}

function Get-WinMintBuildOutputPathFromPipelineResult {
    param(
        [AllowNull()][object]$PipelineResult,
        [Parameter(Mandatory)][AllowEmptyString()][string]$FallbackPath
    )

    foreach ($item in @($PipelineResult)) {
        if ($null -eq $item) { continue }
        if (-not $item.PSObject.Properties['OutputIsoPath']) { continue }

        $path = [string]$item.OutputIsoPath
        if (-not [string]::IsNullOrWhiteSpace($path)) { return $path }
    }

    return $FallbackPath
}

function Invoke-WinMintIsoBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [switch]$DryRun,
        [scriptblock]$ProgressHandler
    )

    Write-WinMintProgress `
        -Stage 'Start' `
        -Level Section `
        -Message 'WinMint shared build engine starting' `
        -ProgressHandler $ProgressHandler

    # Fail fast on non-elevated runs. Dry-run still inspects/mounts ISO content,
    # validates DISM/driver paths, and may follow source-prep output produced by
    # UUP Dump, so the whole build surface uses one elevation rule.
    if (-not (Test-WinMintAdministrator)) {
        Write-WinMintProgress -Stage 'Validate' -Level Error `
            -Message 'WinMint requires Administrator for builds, dry-runs, validation, source prep, and driver checks.' `
            -ProgressHandler $ProgressHandler
        throw 'Not running elevated; WinMint requires Administrator.'
    }

    $pre = Test-WinMintBuildPrerequisite -Config $Config -AllowMissingSourceIso:$DryRun
    foreach ($w in $pre.Warnings) { Write-WinMintProgress -Stage 'Validate' -Level Warn -Message $w -ProgressHandler $ProgressHandler }
    foreach ($f in $pre.Failures) { Write-WinMintProgress -Stage 'Validate' -Level Error -Message $f -ProgressHandler $ProgressHandler }
    if (-not $pre.Passed) {
        $report = New-WinMintBuildReport -Config $Config -DetectedArchitecture $Config.Architecture -Warnings $pre.Warnings -Failures $pre.Failures
        $paths = Save-WinMintBuildReport -Report $report
        throw "Build prerequisites failed. Report: $($paths.Json)"
    }

    $sourceIsoAvailable = -not [string]::IsNullOrWhiteSpace($Config.SourceIso) -and (Test-Path -LiteralPath $Config.SourceIso)
    $detected = if ($sourceIsoAvailable) { Get-WinMintIsoArchitectureHint -Path $Config.SourceIso } else { $null }
    if (-not $detected) { $detected = $Config.Architecture }
    $sourceMessage = if ($sourceIsoAvailable) {
        "Source ISO found; architecture hint: $detected"
    }
    else {
        "Dry run architecture: $detected"
    }
    Write-WinMintProgress `
        -Stage 'Validate' `
        -Level OK `
        -Message $sourceMessage `
        -ProgressHandler $ProgressHandler
    Write-WinMintProgress `
        -Stage 'Profile' `
        -Level OK `
        -Message "Profile: $($Config.Profile); editors: $($Config.Editors -join ', ')" `
        -ProgressHandler $ProgressHandler

    $report = New-WinMintBuildReport -Config $Config -DetectedArchitecture $detected -Warnings $pre.Warnings
    $paths = Save-WinMintBuildReport -Report $report
    Write-WinMintProgress -Stage 'Report' -Level OK -Message "Wrote $($paths.Json)" -ProgressHandler $ProgressHandler
    Initialize-WinMintBuildManifest -Config $Config
    if ($DryRun -and -not $sourceIsoAvailable) {
        Write-WinMintProgress `
            -Stage 'DryRun' `
            -Level OK `
            -Message 'Profile-only dry run completed. Provide an ISO to generate autounattend and setup artifacts.' `
            -ProgressHandler $ProgressHandler
        $manifestPath = Save-WinMintBuildManifest -OutputDir (Get-WinMintOutputDirectory) -DryRun
        if ($manifestPath) {
            Write-WinMintProgress -Stage 'Report' -Level OK -Message "Wrote $manifestPath" -ProgressHandler $ProgressHandler
        }
        return [pscustomobject]@{ Report = $report; Paths = $paths; OutputPath = (Get-WinMintOutputDirectory) }
    }
    if (Get-Command Invoke-WinMintIsoPipeline -ErrorAction SilentlyContinue) {
        $stage = if ($DryRun) { 'DryRun' } else { 'Build' }
        Write-WinMintProgress `
            -Stage $stage `
            -Level Section `
            -Message 'Invoking ISO pipeline' `
            -ProgressHandler $ProgressHandler
        if (Get-Command Initialize-ConsoleUtf8ForSpectre -ErrorAction SilentlyContinue) {
            Initialize-ConsoleUtf8ForSpectre
        }
        if ((Get-Command Initialize-Spectre -ErrorAction SilentlyContinue) -and
            -not (Get-Command Write-SpectreHost -ErrorAction SilentlyContinue)) {
            Initialize-Spectre
        }
        $hadPreviousProgressHandler = $false
        $previousProgressHandler = $null
        $previousProgressVariable = Get-Variable -Name WinMintProgressHandler -Scope Script -ErrorAction SilentlyContinue
        if ($previousProgressVariable) {
            $hadPreviousProgressHandler = $true
            $previousProgressHandler = $previousProgressVariable.Value
        }
        try {
            if ($ProgressHandler) {
                $script:WinMintProgressHandler = $ProgressHandler
            }
            $pipeline = Invoke-WinMintIsoPipeline `
                -BuildConfig $Config `
                -DryRun:$DryRun `
                -ExportHostDrivers:$Config.ExportHostDrivers `
                -NoServicedWimCache:$Config.NoServicedWimCache
            $pipelineOutputIso = Get-WinMintBuildOutputPathFromPipelineResult -PipelineResult $pipeline -FallbackPath ''
            try {
                $manifestPath = Save-WinMintBuildManifest `
                    -OutputDir (Get-WinMintOutputDirectory) `
                    -OutputIsoPath $pipelineOutputIso `
                    -DryRun:$DryRun
                if ($manifestPath) {
                    Write-WinMintProgress -Stage 'Report' -Level OK -Message "Wrote $manifestPath" -ProgressHandler $ProgressHandler
                }
            }
            catch {
                $manifestError = $_
                $isoExists = -not [string]::IsNullOrWhiteSpace($pipelineOutputIso) -and (Test-Path -LiteralPath $pipelineOutputIso)
                if (-not $isoExists -and -not $DryRun) { throw }
                Write-WinMintProgress `
                    -Stage 'Report' `
                    -Level Warn `
                    -Message "Build output completed, but manifest save failed: $($manifestError.Exception.Message)" `
                    -ProgressHandler $ProgressHandler
            }
        }
        catch {
            Save-WinMintBuildManifest -OutputDir (Get-WinMintOutputDirectory) -Failed | Out-Null
            throw
        }
        finally {
            if ($hadPreviousProgressHandler) {
                $script:WinMintProgressHandler = $previousProgressHandler
            } else {
                Remove-Variable -Name WinMintProgressHandler -Scope Script -ErrorAction SilentlyContinue
            }
        }
        $resultPath = Get-WinMintBuildOutputPathFromPipelineResult -PipelineResult $pipeline -FallbackPath (Get-WinMintOutputDirectory)
    }
    else {
        $resultPath = Get-WinMintOutputDirectory
        Write-WinMintProgress `
            -Stage 'Build' `
            -Level Warn `
            -Message 'ISO pipeline is not loaded; reports only.' `
            -ProgressHandler $ProgressHandler
    }
    return [pscustomobject]@{ Report = $report; Paths = $paths; OutputPath = $resultPath }
}

Set-Alias -Name Test-WinMintBuildPrerequisites -Value Test-WinMintBuildPrerequisite

function Start-WinMintBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$BuildProfile,
        [switch]$DryRun,
        [scriptblock]$ProgressHandler
    )

    $config = New-WinMintBuildConfig -BuildProfile $BuildProfile

    try {
        # Strip ALL password / auto-logon state from the public artifact so it
        # round-trips through -ResumeProfile as a passwordless profile. Leaving
        # passwordSet=true while clearing the secret tripped Test-WinMintBuild-
        # Prerequisite ("passwordSet is true but passwordIncluded is false")
        # and made the published artifact unusable as a resume input.
        $pubProfile = $BuildProfile | ConvertTo-Json -Depth 16 | ConvertFrom-Json
        $pubProfile.identity.PSObject.Properties.Remove('password')
        $pubProfile.identity.passwordIncluded = $false
        $pubProfile.identity.passwordSet = $false
        $pubProfile.identity.autoLogon = $false
        $artifactPath = Join-Path (Get-WinMintOutputDirectory) 'WinMint-BuildProfile.json'
        $null = Save-WinMintBuildProfile -BuildProfile $pubProfile -Path $artifactPath
        Write-WinMintProgress -Stage 'Profile' -Level OK -Message "Build profile: $artifactPath" -ProgressHandler $ProgressHandler
    }
    catch {
        Write-WinMintProgress -Stage 'Profile' -Level Warn -Message "Could not save profile artifact: $_" -ProgressHandler $ProgressHandler
    }

    Invoke-WinMintIsoBuild -Config $config -DryRun:$DryRun -ProgressHandler $ProgressHandler
}
