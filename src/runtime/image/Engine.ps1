#Requires -Version 7.3

function New-WinMintBuildConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$BuildProfile
    )

    Assert-WinMintBuildProfile -BuildProfile $BuildProfile

    $packages = Get-WinMintPath -Name ConfigRoot -ChildPath 'packages.json'
    $source = Get-WinMintProfileSetting $BuildProfile 'source' @{}
    $target = Get-WinMintProfileSetting $BuildProfile 'target' @{}
    $identity = Get-WinMintProfileSetting $BuildProfile 'identity' @{}
    $regional = Get-WinMintProfileSetting $BuildProfile 'regional' @{}
    $drivers = Get-WinMintProfileSetting $BuildProfile 'drivers' @{}
    $desktop = Get-WinMintProfileSetting $BuildProfile 'desktop' @{}
    $development = Get-WinMintProfileSetting $BuildProfile 'development' @{}
    $featureToggles = Get-WinMintProfileSetting $BuildProfile 'features' @{}
    $updates = Get-WinMintProfileSetting $BuildProfile 'updates' @{
        mode = 'None'
        targetFeatureVersion = '25H2'
        releaseCadence = 'BRelease'
        includeOptionalPreviews = $false
        payloadRoot = ''
        qualitySecurity = $true
        dynamicUpdate = $true
        defender = $true
        dotnet = $true
        provisionedApps = $true
    }
    $wsl = Get-WinMintProfileSetting $development 'wsl' @{}
    $removals = Get-WinMintProfileSetting $BuildProfile 'removals' @{}
    $privacy = Get-WinMintProfileSetting $BuildProfile 'privacy' @{}
    $tweaks = Get-WinMintProfileSetting $BuildProfile 'tweaks' @{}

    $profileName = [string](Get-WinMintProfileSetting $BuildProfile 'profileName' 'WinMint')
    # Subtractive model: the default build removes everything; opt-in keep flags
    # suppress a domain's removal.
    $keep = Get-WinMintProfileSetting $BuildProfile 'keep' @{}
    $keepEdge = [bool](Get-WinMintProfileSetting $keep 'edge' $false)
    $keepGaming = [bool](Get-WinMintProfileSetting $keep 'gaming' $false)
    $keepCopilot = [bool](Get-WinMintProfileSetting $keep 'copilot' $false)
    $selectedEditors = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $development 'editors' @()))
    $selectedBrowsers = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $development 'browsers' @()))
    $driverSource = [string](Get-WinMintProfileSetting $drivers 'source' 'None')
    $driverPath = [string](Get-WinMintProfileSetting $drivers 'path' '')
    $exportHostDrivers = ($driverSource -eq 'Host')
    $wsl2Distros = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $wsl 'distros' @()))
    $wsl2Distro = if ($wsl2Distros.Count -eq 0) { 'None' } elseif ($wsl2Distros.Count -eq 1) { $wsl2Distros[0] } else { $wsl2Distros -join ',' }
    $layers = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $desktop 'layers' @()))
    $desktopUi = @($layers | Where-Object { $_ -and $_ -ne 'standard' }).Count -gt 0
    $launcher = [string](Get-WinMintProfileSetting $featureToggles 'launcher' '')
    if ([string]::IsNullOrWhiteSpace($launcher)) {
        $launcher = 'None'
    }
    if ($launcher -eq 'None' -and $layers -contains 'thide') {
        $launcher = 'Raycast'
    }
    if ($launcher -notin @('None', 'Raycast')) { $launcher = 'None' }
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
    $formFactor = [string](Get-WinMintProfileSetting $target 'formFactor' 'Auto')
    if ($formFactor -notin @('Auto', 'Laptop', 'Desktop')) { $formFactor = 'Auto' }
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
    $features.Add('OpenSSH.Client')
    # Baseline developer runtime: WSL2 and its VM plumbing are always enabled,
    # even when no distro is selected yet.
    $features.Add('Microsoft-Windows-Subsystem-Linux')
    $features.Add('VirtualMachinePlatform')
    $registryTweaks = [System.Collections.Generic.List[string]]::new()
    $tweakDarkMode = [bool](Get-WinMintProfileSetting $tweaks 'darkMode' $true)
    $tweakFileExtensions = [bool](Get-WinMintProfileSetting $tweaks 'fileExtensions' $true)
    $tweakStickyKeys = [bool](Get-WinMintProfileSetting $tweaks 'stickyKeys' $true)
    $tweakHardwareBypass = [bool](Get-WinMintProfileSetting $tweaks 'hardwareBypass' $false)
    $tweakDmaInterop = [bool](Get-WinMintProfileSetting $tweaks 'dmaInterop' $true)
    $updatePolicy = 'All'
    $privacyTelemetry = [bool](Get-WinMintProfileSetting $privacy 'telemetry' $true)
    $privacyAdvertisingId = [bool](Get-WinMintProfileSetting $privacy 'advertisingId' $true)
    $privacyLocation = [bool](Get-WinMintProfileSetting $privacy 'location' $true)
    $privacyTimeline = [bool](Get-WinMintProfileSetting $privacy 'timeline' $true)
    $aiRemoval = New-WinMintAiRemovalConfig -Removals $removals -KeepCopilot $keepCopilot
    $appxCatalog = Get-WinMintAppxRemovalCatalog
    $dmaSetupRegion = Resolve-WinMintDmaInteropSetupRegion
    $restoreUserLocale = [string](Get-WinMintProfileSetting $regional 'userLocale' '')
    $restoreHomeLocationGeoId = [int](Get-WinMintProfileSetting $regional 'homeLocationGeoId' (Resolve-WinMintRegionGeoId -CultureName $restoreUserLocale))
    $dmaSetupUserLocale = if ($tweakDmaInterop) { [string]$dmaSetupRegion.Culture } else { $restoreUserLocale }
    $dmaSetupHomeLocationGeoId = if ($tweakDmaInterop) { [int]$dmaSetupRegion.GeoId } else { $restoreHomeLocationGeoId }
    # Curation: each registry tweak module (src/runtime/image/Private/Image/Tweaks/*.ps1)
    # carries its own appliesTo predicate. Build the normalized context once and let
    # Get-WinMintSelectedRegistryTweaks evaluate every module against it.
    $tweakContext = New-WinMintTweakContext `
        -PrivacyTelemetry $privacyTelemetry `
        -PrivacyAdvertisingId $privacyAdvertisingId `
        -PrivacyLocation $privacyLocation `
        -KeepGaming $keepGaming `
        -KeepCopilot $keepCopilot `
        -DesktopUi $desktopUi `
        -DiskMode $diskMode `
        -TweakHardwareBypass $tweakHardwareBypass `
        -TweakFileExtensions $tweakFileExtensions
    $registryTweaks.AddRange([string[]]@(Get-WinMintSelectedRegistryTweaks -Context $tweakContext))
    $profileEffectiveAppx = @(ConvertTo-WinMintProfileStringArray (Get-WinMintProfileSetting $removals 'effectiveAppx' @()))
    $baseAppxRemovalPrefixes = if ($profileEffectiveAppx.Count -gt 0) {
        @($profileEffectiveAppx)
    }
    else {
        @(Get-WinMintProfileAppxRemovalPrefix -Removals $removals)
    }
    $appxRemovalPrefixes = @($baseAppxRemovalPrefixes + @($aiRemoval.AppxPrefixes) | Where-Object { $_ } | Sort-Object -Unique)
    if ($keepCopilot) {
        # Keep the Copilot+ AI assistant packages; Recall is not an AppX (removed
        # as an optional feature) so it is unaffected here.
        $appxRemovalPrefixes = @($appxRemovalPrefixes | Where-Object { $_ -notin @('Microsoft.Copilot', 'Microsoft.Windows.Copilot', 'Microsoft.Windows.AIHub') })
    }

    $editionMode = Get-WinMintProfileEditionMode -Settings $target
    $edition = [string](Get-WinMintProfileSetting $target 'edition' '')
    if ($editionMode -eq 'Fixed' -and [string]::IsNullOrWhiteSpace($edition)) {
        $edition = 'Windows 11 Home'
    }
    # Generic product key to inject into the answer file (empty = keyless default).
    # Resolved by the CLI/headless layer from the -GenericProductKey flag and the
    # build host's firmware-key presence; the engine just carries it through.
    $productKey = [string](Get-WinMintProfileSetting $target 'productKey' '')
    [pscustomobject]@{
        Profile = $profileName
        Keep = [pscustomobject]@{ Edge = $keepEdge; Gaming = $keepGaming; Copilot = $keepCopilot }
        SourceIso = [string](Get-WinMintProfileSetting $source 'isoPath' '')
        Architecture = [string](Get-WinMintProfileSetting $source 'architecture' '')
        EditionMode = $editionMode
        Edition = $edition
        ProductKey = $productKey
        TargetDevice = [string](Get-WinMintProfileSetting $target 'device' 'DifferentPC')
        FormFactor = $formFactor
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
        # Secondary input languages (keyboards) to add while the display language stays en-US.
        # 'Auto' (default) replicates the build host's current keyboard config; resolved here so
        # the rest of the pipeline + FirstLogon receive a concrete list.
        SecondaryInputLanguages = @(Resolve-WinMintSecondaryInputLanguages `
                -Raw (Get-WinMintProfileSetting $regional 'secondaryInputLanguages' 'Auto') `
                -UILanguage ([string](Get-WinMintProfileSetting $regional 'uiLanguage' 'en-US')))
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
                'Default DMA interoperability uses Ireland during setup, then FirstLogon restores the configured visible regional defaults and location-services posture.'
            } else {
                'Disabled; setup uses the configured regional defaults.'
            }
        }
        ExportHostDrivers = $exportHostDrivers
        Editors = @($selectedEditors)
        Browsers = @($selectedBrowsers)
        InstallWindhawk = ($layers -contains 'windhawk')
        InstallYasb = ($layers -contains 'yasb')
        InstallThide = ($layers -contains 'thide')
        InstallKomorebi = ($layers -contains 'komorebi')
        InstallNilesoft = ($layers -contains 'nilesoft')
        Launcher = $launcher
        InstallRaycast = $installRaycast
        LiveInstallAudit = $enableLiveInstallAudit
        PhoneLink = $enablePhoneLink
        Updates = [pscustomobject]@{
            Mode = [string](Get-WinMintProfileSetting $updates 'mode' 'None')
            TargetFeatureVersion = [string](Get-WinMintProfileSetting $updates 'targetFeatureVersion' '25H2')
            ReleaseCadence = [string](Get-WinMintProfileSetting $updates 'releaseCadence' 'BRelease')
            IncludeOptionalPreviews = [bool](Get-WinMintProfileSetting $updates 'includeOptionalPreviews' $false)
            PayloadRoot = [string](Get-WinMintProfileSetting $updates 'payloadRoot' '')
            QualitySecurity = [bool](Get-WinMintProfileSetting $updates 'qualitySecurity' $true)
            DynamicUpdate = [bool](Get-WinMintProfileSetting $updates 'dynamicUpdate' $true)
            Defender = [bool](Get-WinMintProfileSetting $updates 'defender' $true)
            DotNet = [bool](Get-WinMintProfileSetting $updates 'dotnet' $true)
            ProvisionedApps = [bool](Get-WinMintProfileSetting $updates 'provisionedApps' $true)
        }
        Wsl2Distro = $wsl2Distro
        Wsl2Distros = @($wsl2Distros)
        AppxPackages = @($appxRemovalPrefixes)
        AppxCatalogVersion = [int](Get-WinMintProfileSetting $appxCatalog 'catalogVersion' 1)
        PrimaryAssumption = 'Windows11HomeSingleLanguageEnUS'
        AiRemoval = $aiRemoval
        RegistryTweaks = $registryTweaks.ToArray()
        TelemetryTaskPatterns = @(
            'Microsoft Compatibility Appraiser'
            'ProgramDataUpdater'
            'Consolidator'
            'UsbCeip'
            'DmClient'
            'QueueReporting'
        )
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
        SetupScripts = @(
            'SetupComplete.cmd', 'SetupComplete.ps1', 'SetupComplete\*.ps1', 'Specialize.ps1',
            'DefaultUser.ps1', 'FirstLogon.ps1', 'FirstLogon.Support.ps1',
            'FirstLogon.Transaction.ps1', 'FirstLogon.Runtime.ps1', 'WinMintAgent', 'ViVeTool'
        )
        Assets = @('fonts', 'cursors', 'PowerShell 7', 'windows-terminal', 'winget')
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

    $fontChecks = @(
        @{ Name = 'Cascadia Code font'; Patterns = @('*CascadiaCodeNF-Regular.ttf'); CacheHit = { Get-WinMintCascadiaNerdFontCacheHit } },
        @{ Name = 'Monaspace Nerd Font'; Patterns = @('*Monaspace*NF*.ttf', '*Monaspace*NerdFont*.ttf'); CacheHit = { Get-WinMintMonaspaceNerdFontCacheHit } }
    )
    foreach ($check in $fontChecks) {
        $font = $null
        if (Test-Path -LiteralPath $FontDir) {
            foreach ($pattern in @($check.Patterns)) {
                $font = Get-ChildItem -LiteralPath $FontDir -Filter $pattern -File -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                if ($font) { break }
            }
        }
        if (-not $font) {
            $cachedRoot = & $check.CacheHit
            if ($cachedRoot) {
                $ttfDir = Join-Path $cachedRoot 'ttf'
                foreach ($pattern in @($check.Patterns)) {
                    $font = Get-ChildItem -LiteralPath $ttfDir -Filter $pattern -File -ErrorAction SilentlyContinue |
                        Select-Object -First 1
                    if ($font) { break }
                }
            }
        }
        if ($font) { $found[$check.Name] = $font.FullName } else { $missing.Add($check.Name) | Out-Null }
    }

    [pscustomobject]@{
        Complete = ($missing.Count -eq 0)
        Missing = $missing.ToArray()
        Found = $found
    }
}

function New-WinMintBuildPreflightContext {
    [CmdletBinding()]
    param(
        [ValidateSet('Build', 'DryRun', 'ValidateOnly')][string]$RunMode = 'Build'
    )

    $sourceIsoPolicy = if ($RunMode -eq 'Build') { 'Required' } else { 'ProfileOnlyOptional' }

    [pscustomobject]@{
        RunMode = $RunMode
        SourceIsoPolicy = $sourceIsoPolicy
        EnforceLocalAccountPassword = ($RunMode -eq 'Build')
        RequireOnlinePayloadCache = ($RunMode -eq 'Build')
    }
}

function Test-WinMintPreflightAllowsProfileOnlySource {
    param(
        [AllowNull()]$PreflightContext
    )

    if ($null -eq $PreflightContext) { return $false }

    $sourceIsoPolicy = $PreflightContext.PSObject.Properties['SourceIsoPolicy']
    if ($sourceIsoPolicy) {
        return ([string]$sourceIsoPolicy.Value -eq 'ProfileOnlyOptional')
    }

    $legacyAllowMissingSourceIso = $PreflightContext.PSObject.Properties['AllowMissingSourceIso']
    if ($legacyAllowMissingSourceIso) {
        return [bool]$legacyAllowMissingSourceIso.Value
    }

    return $false
}

function Test-WinMintBuildPrerequisite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [ValidateSet('Build', 'DryRun', 'ValidateOnly')][string]$RunMode = 'Build',
        [AllowNull()]$PreflightContext = $null,
        [switch]$AllowMissingSourceIso
    )

    if ($null -eq $PreflightContext) {
        if ($AllowMissingSourceIso -and $RunMode -eq 'Build') {
            $RunMode = 'DryRun'
        }
        $PreflightContext = New-WinMintBuildPreflightContext -RunMode $RunMode
    }

    $warnings = [System.Collections.Generic.List[string]]::new()
    $failures = [System.Collections.Generic.List[string]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    function Add-WinMintBuildPreflightFinding {
        param(
            [Parameter(Mandatory)][ValidateSet('warning', 'failure')][string]$Severity,
            [Parameter(Mandatory)][string]$Code,
            [Parameter(Mandatory)][string]$Message
        )

        $findings.Add([pscustomobject]@{
            Severity = $Severity
            Code = $Code
            Message = $Message
        }) | Out-Null
        if ($Severity -eq 'warning') {
            $warnings.Add($Message) | Out-Null
        }
        else {
            $failures.Add($Message) | Out-Null
        }
    }

    $sourceIsoMissing = [string]::IsNullOrWhiteSpace($Config.SourceIso)
    if ($sourceIsoMissing) {
        if (Test-WinMintPreflightAllowsProfileOnlySource -PreflightContext $PreflightContext) {
            Add-WinMintBuildPreflightFinding `
                -Severity warning `
                -Code 'source.iso.missing.profileOnlyDryRun' `
                -Message 'Dry run profile-only mode: no source ISO was provided, so WIM metadata and setup artifacts are skipped.'
        }
        else {
            Add-WinMintBuildPreflightFinding -Severity failure -Code 'source.iso.missing' -Message 'Source ISO is not set.'
        }
    }
    elseif (-not (Test-Path -LiteralPath $Config.SourceIso)) {
        Add-WinMintBuildPreflightFinding -Severity failure -Code 'source.iso.notFound' -Message "Source ISO not found: $($Config.SourceIso)"
    }
    $profileOnlyDryRun = (Test-WinMintPreflightAllowsProfileOnlySource -PreflightContext $PreflightContext) -and $sourceIsoMissing
    if (-not $profileOnlyDryRun -and [string]::IsNullOrWhiteSpace([string]$Config.Architecture)) {
        Add-WinMintBuildPreflightFinding -Severity failure -Code 'source.architecture.missing' -Message 'Architecture is not set; oscdimg cannot pick a boot layout without it.'
    }
    if (-not (Test-Path -LiteralPath $Config.PackagesManifest)) {
        Add-WinMintBuildPreflightFinding -Severity warning -Code 'packages.manifest.missing' -Message "Package manifest missing: $($Config.PackagesManifest)"
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$Config.Architecture)) {
        try {
            $manifest = Get-Content -LiteralPath $Config.PackagesManifest -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($toolId in @(Get-WinMintWingetHandoffToolIds -Config $Config)) {
                $property = if ($manifest.tools) { $manifest.tools.PSObject.Properties[$toolId] } else { $null }
                if (-not $property) { continue }
                $tool = $property.Value
                $unsupported = @()
                if ($tool.PSObject.Properties['unsupportedArchitectures']) {
                    if ($tool.unsupportedArchitectures -is [array]) {
                        $unsupported = @($tool.unsupportedArchitectures | ForEach-Object { ([string]$_).ToLowerInvariant() })
                    }
                    else {
                        $unsupported = @($tool.unsupportedArchitectures.PSObject.Properties.Name | ForEach-Object { ([string]$_).ToLowerInvariant() })
                    }
                }
                if ($unsupported -contains ([string]$Config.Architecture).ToLowerInvariant()) {
                    $displayName = if ($tool.PSObject.Properties['displayName']) { [string]$tool.displayName } else { [string]$toolId }
                    $message = @(
                        "$displayName is selected, but packages.json marks $($Config.Architecture)"
                        'as unsupported for its package source. FirstLogon will skip that package'
                        'on this architecture.'
                    ) -join ' '
                    Add-WinMintBuildPreflightFinding -Severity warning `
                        -Code 'packages.tool.architectureUnsupported' `
                        -Message $message
                }
            }
        }
        catch {
            $message = "Package manifest could not be inspected for architecture support: $($_.Exception.Message)"
            Add-WinMintBuildPreflightFinding -Severity warning `
                -Code 'packages.manifest.readFailed' `
                -Message $message
        }
    }
    if (-not $profileOnlyDryRun -and [bool]$PreflightContext.RequireOnlinePayloadCache -and -not (Test-WinMintGitHubApiReachable -TimeoutSec 5)) {
        $cache = Get-WinMintOfflinePayloadCacheStatus -Architecture ([string]$Config.Architecture)
        if ($cache.Complete) {
            $message = @(
                'No internet connectivity to api.github.com; cached PowerShell 7,'
                'ViVeTool, winget, Cascadia, and Monaspace payloads are present,'
                'so the build can continue offline.'
            ) -join ' '
            Add-WinMintBuildPreflightFinding -Severity warning `
                -Code 'network.github.offline.cacheComplete' `
                -Message $message
        }
        else {
            $message = @(
                'No internet connectivity to api.github.com and offline payload cache is incomplete.'
                "Missing: $($cache.Missing -join ', ')."
                'Connect and retry once to refresh the cache.'
            ) -join ' '
            Add-WinMintBuildPreflightFinding -Severity failure `
                -Code 'network.github.offline.cacheIncomplete' `
                -Message $message
        }
    }
    if ($Config.PasswordSet -and -not $Config.PasswordIncluded) {
        $message = @(
            'The build profile says a password was set, but the password secret is not included.'
            'Re-enter the password in the UI before building.'
        ) -join ' '
        Add-WinMintBuildPreflightFinding -Severity failure `
            -Code 'identity.password.secretMissing' `
            -Message $message
    }
    if ($Config.Updates -and [string]$Config.Updates.Mode -ne 'None') {
        if ([string]$Config.Updates.Mode -ne 'Stable25H2') {
            Add-WinMintBuildPreflightFinding -Severity failure -Code 'updates.mode.unsupported' -Message "Unsupported image update mode: $($Config.Updates.Mode)"
        }
        if ([string]$Config.Updates.TargetFeatureVersion -ne '25H2') {
            Add-WinMintBuildPreflightFinding -Severity failure -Code 'updates.featureVersion.unsupported' -Message 'Stable image updates are limited to Windows 11 25H2 broad-release media.'
        }
        if ([string]$Config.Updates.ReleaseCadence -ne 'BRelease' -or [bool]$Config.Updates.IncludeOptionalPreviews) {
            Add-WinMintBuildPreflightFinding -Severity failure -Code 'updates.releaseCadence.unsupported' -Message 'Stable image updates must use Patch Tuesday B-release payloads; optional C/D previews are not accepted.'
        }
        $payloadRoot = [string]$Config.Updates.PayloadRoot
        if ($profileOnlyDryRun) {
            Add-WinMintBuildPreflightFinding -Severity warning -Code 'updates.payloadRoot.skippedProfileOnlyDryRun' -Message "Profile-only dry run: Stable25H2 update payload root was not checked: $payloadRoot"
        }
        elseif ([string]::IsNullOrWhiteSpace($payloadRoot)) {
            Add-WinMintBuildPreflightFinding -Severity failure -Code 'updates.payloadRoot.missing' -Message 'Stable25H2 image updates require updates.payloadRoot with explicit Microsoft update/MSIX payloads.'
        }
        elseif (-not (Test-Path -LiteralPath $payloadRoot -PathType Container)) {
            Add-WinMintBuildPreflightFinding -Severity failure -Code 'updates.payloadRoot.notFound' -Message "Update payload root not found: $payloadRoot"
        }
    }
    if ($Config.AutoLogon -and [string]::IsNullOrWhiteSpace([string]$Config.Password)) {
        Add-WinMintBuildPreflightFinding -Severity failure -Code 'identity.autologon.passwordMissing' -Message 'Autologon requires an included account password.'
    }
    # A pre-created passwordless local account still triggers the Windows 11 OOBE
    # "Create a password" page (Microsoft hardened this in 24H2/25H2; omitting the
    # password element does not suppress it), which stops the otherwise-unattended
    # install. Require a password for real Local-account builds. Dry runs skip this
    # because they generate artifacts without installing.
    if ([bool]$PreflightContext.EnforceLocalAccountPassword -and
        [string]$Config.AccountMode -eq 'Local' -and
        [string]::IsNullOrWhiteSpace([string]$Config.Password)) {
        Add-WinMintBuildPreflightFinding -Severity failure -Code 'identity.localAccount.passwordRequired' -Message (@(
                'Local-account builds require a password, otherwise the unattended install stops'
                'at the Windows 11 OOBE "Create a password" page. Re-author the profile with'
                '-Password, -PasswordPath, or -PasswordEnvVar, or use -AccountMode MicrosoftOobe'
                'to create the account interactively during setup.'
            ) -join ' ')
    }
    if ($Config.Architecture -and $Config.SourceIso) {
        $hint = Get-WinMintIsoArchitectureHint -Path $Config.SourceIso
        if ($hint -and $hint -ne $Config.Architecture) {
            Add-WinMintBuildPreflightFinding -Severity warning -Code 'source.architecture.filenameMismatch' -Message "ISO filename suggests $hint, but config selected $($Config.Architecture)."
        }
    }
    if ($Config.TargetDevice -eq 'ThisPC' -and $Config.Architecture) {
        $hostArch = Get-BuildHostProcessorArchitecture
        if ($hostArch -ne $Config.Architecture) {
            $message = @(
                "This PC target requires the ISO architecture ($($Config.Architecture))"
                "to match this PC ($hostArch)."
                'Choose Different PC for cross-machine builds.'
            ) -join ' '
            Add-WinMintBuildPreflightFinding -Severity failure `
                -Code 'target.thisPc.architectureMismatch' `
                -Message $message
        }
    }
    if ($Config.Drivers.Source -eq 'Host' -and $Config.Architecture) {
        $hostArch = Get-BuildHostProcessorArchitecture
        if ($hostArch -ne $Config.Architecture) {
            $message = @(
                "Mirror PC drivers require the build PC architecture ($hostArch)"
                "to match the target ISO architecture ($($Config.Architecture))."
            ) -join ' '
            Add-WinMintBuildPreflightFinding -Severity failure `
                -Code 'drivers.host.architectureMismatch' `
                -Message $message
        }
        if (
            -not (Get-Command Export-WindowsDriver -ErrorAction SilentlyContinue) -and
            -not (Get-Command pnputil.exe -CommandType Application -ErrorAction SilentlyContinue)
        ) {
            $message = @(
                'Mirror PC drivers were requested, but neither Export-WindowsDriver nor'
                'pnputil.exe is available. Install/configure Windows driver export tooling'
                'or choose a custom driver pack.'
            ) -join ' '
            Add-WinMintBuildPreflightFinding -Severity failure `
                -Code 'drivers.host.exportToolMissing' `
                -Message $message
        }
    }
    if ($Config.InstallWindhawk) {
        $windhawkBootstrap = Get-WinMintPath -Name RuntimeSetupRoot -ChildPath 'WindhawkBootstrap.ps1'
        $virtualDesktopFlyouts = Get-WinMintPath -Name RuntimeSetupRoot -ChildPath 'DisableVirtualDesktopFlyouts.ps1'
        $windhawkPreset = Join-Path (Get-WinMintRepositoryRoot) 'assets\runtime\desktop\windhawk\preset.json'
        if (-not (Test-Path -LiteralPath $windhawkBootstrap)) {
            Add-WinMintBuildPreflightFinding -Severity failure -Code 'assets.windhawk.bootstrapMissing' -Message "WinMint Windhawk bootstrap script is missing from the repository: $windhawkBootstrap"
        }
        if (-not (Test-Path -LiteralPath $virtualDesktopFlyouts)) {
            Add-WinMintBuildPreflightFinding -Severity failure -Code 'assets.windhawk.flyoutScriptMissing' -Message "WinMint virtual desktop flyout script is missing from the repository: $virtualDesktopFlyouts"
        }
        if (-not (Test-Path -LiteralPath $windhawkPreset)) {
            Add-WinMintBuildPreflightFinding -Severity failure -Code 'assets.windhawk.presetMissing' -Message "WinMint Windhawk preset is missing from the repository: $windhawkPreset"
        }
    }
    if ($Config.InstallYasb) {
        foreach ($asset in @('assets\runtime\desktop\yasb\config.yaml', 'assets\runtime\desktop\yasb\styles.css')) {
            $path = Join-Path (Get-WinMintRepositoryRoot) $asset
            if (-not (Test-Path -LiteralPath $path)) {
                Add-WinMintBuildPreflightFinding -Severity failure -Code 'assets.yasb.presetMissing' -Message "WinMint YASB preset asset is missing from the repository: $path"
            }
        }
    }
    if ($Config.InstallKomorebi) {
        foreach ($asset in @('assets\runtime\desktop\komorebi\komorebi.json', 'assets\runtime\desktop\komorebi\applications.json', 'assets\runtime\desktop\komorebi\whkdrc')) {
            $path = Join-Path (Get-WinMintRepositoryRoot) $asset
            if (-not (Test-Path -LiteralPath $path)) {
                Add-WinMintBuildPreflightFinding -Severity failure -Code 'assets.komorebi.presetMissing' -Message "WinMint Komorebi preset asset is missing from the repository: $path"
            }
        }
    }
    if ($Config.Drivers.Source -eq 'Custom') {
        $driverPath = [string]$Config.Drivers.Path
        if ([string]::IsNullOrWhiteSpace($driverPath)) {
            Add-WinMintBuildPreflightFinding -Severity failure -Code 'drivers.custom.pathMissing' -Message 'Custom driver source was selected, but no driver path was provided.'
        }
        elseif (-not (Test-Path -LiteralPath $driverPath)) {
            Add-WinMintBuildPreflightFinding -Severity failure -Code 'drivers.custom.pathNotFound' -Message "Custom driver path not found: $driverPath"
        }
        else {
            $item = Get-Item -LiteralPath $driverPath
            if (-not $item.PSIsContainer -and $item.Extension -notin '.inf', '.msi', '.zip') {
                Add-WinMintBuildPreflightFinding -Severity failure -Code 'drivers.custom.pathUnsupported' -Message "Custom driver path must be a .inf file, .msi file, .zip file, or folder: $driverPath"
            }
        }
    }
    [pscustomobject]@{
        Passed = ($failures.Count -eq 0)
        Warnings = $warnings.ToArray()
        Failures = $failures.ToArray()
        Findings = $findings.ToArray()
        Context = $PreflightContext
    }
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
        [switch]$WriteUsb,
        [int]$UsbDiskNumber = -1,
        [int]$ConfirmUsbDiskNumber = -1,
        [switch]$AllowFixedUsbDisk,
        [scriptblock]$ProgressHandler
    )

    Write-WinMintProgress `
        -Stage 'Start' `
        -Level Section `
        -Message 'WinMint shared build engine starting' `
        -ProgressHandler $ProgressHandler

    # Fail fast on non-elevated runs. Dry-run still inspects/mounts ISO content,
    # validates DISM/driver paths, and may follow source-prep output produced by
    # ISO prep, build, and validate share one elevation rule.
    if (-not (Test-WinMintAdministrator)) {
        Write-WinMintProgress -Stage 'Validate' -Level Error `
            -Message 'WinMint requires Administrator for builds, dry-runs, validation, source prep, and driver checks.' `
            -ProgressHandler $ProgressHandler
        throw 'Not running elevated; WinMint requires Administrator.'
    }

    if (-not $DryRun -and $Config.Updates -and [string]$Config.Updates.Mode -ne 'None') {
        Write-WinMintProgress `
            -Stage 'Updates' `
            -Level Section `
            -Message 'Resolving official Microsoft update payloads' `
            -ProgressHandler $ProgressHandler
        try {
            $acquired = Invoke-WinMintStable25H2UpdatePayloadAcquisition `
                -Updates $Config.Updates `
                -Architecture ([string]$Config.Architecture)
            if ($acquired) {
                Write-WinMintProgress `
                    -Stage 'Updates' `
                    -Level OK `
                    -Message "Resolved $($acquired.PayloadCount) update payload file(s): $($acquired.ManifestPath)" `
                    -ProgressHandler $ProgressHandler
            }
        }
        catch {
            Write-WinMintProgress `
                -Stage 'Updates' `
                -Level Error `
                -Message "Official update payload acquisition failed: $($_.Exception.Message)" `
                -ProgressHandler $ProgressHandler
            throw
        }
    }

    $preflightRunMode = if ($DryRun) { 'DryRun' } else { 'Build' }
    $pre = Test-WinMintBuildPrerequisite -Config $Config -RunMode $preflightRunMode
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
        if ([string]::IsNullOrWhiteSpace([string]$detected)) {
            'Dry run architecture: not set (profile-only; no ISO provided)'
        }
        else {
            "Dry run architecture: $detected"
        }
    }
    Write-WinMintProgress `
        -Stage 'Validate' `
        -Level OK `
        -Message $sourceMessage `
        -ProgressHandler $ProgressHandler
    $installPlan = New-WinMintInstallPlanFromBuildConfig -BuildConfig $Config
    $kept = @()
    if ($Config.Keep.Edge) { $kept += 'Edge' }
    if ($Config.Keep.Gaming) { $kept += 'Gaming' }
    if ($Config.Keep.Copilot) { $kept += 'Copilot' }
    $profileMessage = "Profile: $($Config.Profile)"
    if ($kept.Count) { $profileMessage += "; keep: $($kept -join ', ')" }
    $profileMessage += "; editors: $($Config.Editors -join ', ')"
    if (@($Config.Browsers).Count -gt 0) { $profileMessage += "; browsers: $($Config.Browsers -join ', ')" }
    Write-WinMintProgress `
        -Stage 'Profile' `
        -Level OK `
        -Message $profileMessage `
        -ProgressHandler $ProgressHandler

    $report = New-WinMintBuildReport -Config $Config -DetectedArchitecture $detected -Warnings $pre.Warnings
    $paths = Save-WinMintBuildReport -Report $report
    Write-WinMintProgress -Stage 'Report' -Level OK -Message "Wrote $($paths.Json)" -ProgressHandler $ProgressHandler
    Initialize-WinMintBuildManifest -Config $Config -InstallPlan $installPlan
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
                -NoServicedWimCache:$Config.NoServicedWimCache `
                -InstallPlan $installPlan `
                -WriteUsb:$WriteUsb `
                -UsbDiskNumber $UsbDiskNumber `
                -ConfirmUsbDiskNumber $ConfirmUsbDiskNumber `
                -AllowFixedUsbDisk:$AllowFixedUsbDisk
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
        [switch]$WriteUsb,
        [int]$UsbDiskNumber = -1,
        [int]$ConfirmUsbDiskNumber = -1,
        [switch]$AllowFixedUsbDisk,
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

    Invoke-WinMintIsoBuild `
        -Config $config `
        -DryRun:$DryRun `
        -WriteUsb:$WriteUsb `
        -UsbDiskNumber $UsbDiskNumber `
        -ConfirmUsbDiskNumber $ConfirmUsbDiskNumber `
        -AllowFixedUsbDisk:$AllowFixedUsbDisk `
        -ProgressHandler $ProgressHandler
}
