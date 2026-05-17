#Requires -Version 7.3

function New-WinWSBuildConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$BuildProfile
    )

    Assert-WinWSBuildProfile -BuildProfile $BuildProfile

    $root = Get-WinWSRepositoryRoot
    $packages = Join-Path $root 'config\packages.json'
    $source = Get-WinWSProfileSetting $BuildProfile 'source' @{}
    $target = Get-WinWSProfileSetting $BuildProfile 'target' @{}
    $identity = Get-WinWSProfileSetting $BuildProfile 'identity' @{}
    $regional = Get-WinWSProfileSetting $BuildProfile 'regional' @{}
    $drivers = Get-WinWSProfileSetting $BuildProfile 'drivers' @{}
    $desktop = Get-WinWSProfileSetting $BuildProfile 'desktop' @{}
    $development = Get-WinWSProfileSetting $BuildProfile 'development' @{}
    $wsl = Get-WinWSProfileSetting $development 'wsl' @{}
    $removals = Get-WinWSProfileSetting $BuildProfile 'removals' @{}
    $privacy = Get-WinWSProfileSetting $BuildProfile 'privacy' @{}
    $tweaks = Get-WinWSProfileSetting $BuildProfile 'tweaks' @{}

    $profileName = [string](Get-WinWSProfileSetting $BuildProfile 'profileName' 'Developer')
    $setupOption = [string](Get-WinWSProfileSetting $BuildProfile 'setupOption' 'Minimal')
    if ($setupOption -notin @('Minimal', 'CopilotPlus')) { $setupOption = 'Minimal' }
    $profileGroups = @(ConvertTo-WinWSProfileStringArray (Get-WinWSProfileSetting $BuildProfile 'profileGroups' @()))
    if ($profileGroups.Count -eq 0) {
        $profileGroups = if ($setupOption -eq 'CopilotPlus') { @('Minimal', 'CopilotPlus') } else { @('Minimal') }
    }
    $enableDeveloperGroup = $profileGroups -contains 'Developer'
    $selectedEditors = @(ConvertTo-WinWSProfileStringArray (Get-WinWSProfileSetting $development 'editors' @()))
    $driverSource = [string](Get-WinWSProfileSetting $drivers 'source' 'None')
    $driverPath = [string](Get-WinWSProfileSetting $drivers 'path' '')
    $exportHostDrivers = ($driverSource -eq 'Host')
    $wsl2Distros = @(ConvertTo-WinWSProfileStringArray (Get-WinWSProfileSetting $wsl 'distros' @()))
    $enableWsl = [bool](Get-WinWSProfileSetting $wsl 'enabled' ($wsl2Distros.Count -gt 0)) -or $wsl2Distros.Count -gt 0
    $wsl2Distro = if ($wsl2Distros.Count -eq 0) { 'None' } elseif ($wsl2Distros.Count -eq 1) { $wsl2Distros[0] } else { $wsl2Distros -join ',' }
    $layers = @(ConvertTo-WinWSProfileStringArray (Get-WinWSProfileSetting $desktop 'layers' @()))
    $password = if ([bool](Get-WinWSProfileSetting $identity 'passwordIncluded' $false)) {
        [string](Get-WinWSProfileSetting $identity 'password' '')
    } else {
        ''
    }
    $accountMode = [string](Get-WinWSProfileSetting $identity 'accountMode' 'Local')
    if ($accountMode -notin @('Local', 'MicrosoftOobe')) { $accountMode = 'Local' }
    $passwordSet = [bool](Get-WinWSProfileSetting $identity 'passwordSet' $false)
    $passwordIncluded = [bool](Get-WinWSProfileSetting $identity 'passwordIncluded' $false)
    $diskMode = [string](Get-WinWSProfileSetting $target 'diskMode' 'Manual')
    if ($diskMode -notin @('Manual', 'AutoWipeDisk0', 'DualBootReserved')) { $diskMode = 'Manual' }
    $diskLayout = Get-WinWSProfileSetting $target 'diskLayout' $null
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
    $tweakDarkMode = [bool](Get-WinWSProfileSetting $tweaks 'darkMode' $true)
    $tweakFileExtensions = [bool](Get-WinWSProfileSetting $tweaks 'fileExtensions' $true)
    $tweakStickyKeys = [bool](Get-WinWSProfileSetting $tweaks 'stickyKeys' $true)
    $tweakHardwareBypass = [bool](Get-WinWSProfileSetting $tweaks 'hardwareBypass' $false)
    $updatePolicy = 'All'
    $privacyTelemetry = [bool](Get-WinWSProfileSetting $privacy 'telemetry' $true)
    $privacyAdvertisingId = [bool](Get-WinWSProfileSetting $privacy 'advertisingId' $true)
    $privacyLocation = [bool](Get-WinWSProfileSetting $privacy 'location' $false)
    $privacyTimeline = [bool](Get-WinWSProfileSetting $privacy 'timeline' $true)
    $dmaSetupRegion = Resolve-WinWSDmaInteropSetupRegion
    $dmaSetupUserLocale = [string]$dmaSetupRegion.Culture
    $dmaSetupHomeLocationGeoId = [int]$dmaSetupRegion.GeoId
    $restoreUserLocale = [string](Get-WinWSProfileSetting $regional 'userLocale' '')
    $restoreHomeLocationGeoId = [int](Get-WinWSProfileSetting $regional 'homeLocationGeoId' (Resolve-WinWSRegionGeoId -CultureName $restoreUserLocale))
    if ($tweakHardwareBypass) {
        $registryTweaks.Add('hardware-bypass')
    }
    if ($tweakFileExtensions) {
        $registryTweaks.Add('developer-qol')
    }
    $registryTweaks.Add('uac-no-secure-desktop')
    $registryTweaks.Add('terminal-admin-context')
    if ($privacyTelemetry -or $privacyAdvertisingId) {
        $registryTweaks.Add($(if ($setupOption -eq 'CopilotPlus') { 'edge-policy-copilotplus' } else { 'edge-policy-minimal' }))
    }
    if ($diskMode -eq 'DualBootReserved') {
        $registryTweaks.Add('dual-boot-windows-policy')
    }
    if ($enableDeveloperGroup) {
        $registryTweaks.Add('developer-mode')
        $registryTweaks.Add('powershell-remotesigned')
    }
    if ([bool](Get-WinWSProfileSetting $removals 'microsoftApps' $true)) {
        $registryTweaks.Add('onedrive-policy')
    }
    if ([bool](Get-WinWSProfileSetting $removals 'gaming' $true)) {
        $registryTweaks.Add('gamebar-policy')
    }
    $profileEffectiveAppx = @(ConvertTo-WinWSProfileStringArray (Get-WinWSProfileSetting $removals 'effectiveAppx' @()))
    $appxRemovalPrefixes = if ($profileEffectiveAppx.Count -gt 0) {
        @($profileEffectiveAppx)
    }
    else {
        @(Get-WinWSProfileAppxRemovalPrefix -Removals $removals)
    }

    $rawEditionMode = [string](Get-WinWSProfileSetting $target 'editionMode' 'TargetLicense')
    $editionMode = switch -Regex ($rawEditionMode) {
        '^(TargetLicense|Target|License|Auto)$' { 'TargetLicense'; break }
        '^(Fixed|Forced|Force)$' { 'Fixed'; break }
        default { 'TargetLicense' }
    }
    $edition = [string](Get-WinWSProfileSetting $target 'edition' '')
    if ($editionMode -eq 'Fixed' -and [string]::IsNullOrWhiteSpace($edition)) {
        $edition = 'Windows 11 Pro'
    }
    [pscustomobject]@{
        Profile = $profileName
        ProfileGroups = @($profileGroups)
        SetupOption = $setupOption
        SourceIso = [string](Get-WinWSProfileSetting $source 'isoPath' '')
        Architecture = [string](Get-WinWSProfileSetting $source 'architecture' '')
        EditionMode = $editionMode
        Edition = $edition
        TargetDevice = [string](Get-WinWSProfileSetting $target 'device' 'DifferentPC')
        ComputerName = [string](Get-WinWSProfileSetting $identity 'computerName' '')
        AccountName = [string](Get-WinWSProfileSetting $identity 'accountName' '')
        AccountMode = $accountMode
        Password = $password
        PasswordSet = $passwordSet
        PasswordIncluded = $passwordIncluded
        AutoLogon = [bool](Get-WinWSProfileSetting $identity 'autoLogon' $false)
        DiskMode = $diskMode
        DiskLayout = $diskLayout
        AutoWipeDisk = ($diskMode -in @('AutoWipeDisk0', 'DualBootReserved'))
        CursorPackKind = 'BreezeXLight'
        TimeZoneId = [string](Get-WinWSProfileSetting $regional 'timeZoneId' '')
        InputLocale = [string](Get-WinWSProfileSetting $regional 'inputLocale' '')
        SystemLocale = [string](Get-WinWSProfileSetting $regional 'systemLocale' '')
        UILanguage = [string](Get-WinWSProfileSetting $regional 'uiLanguage' '')
        UILanguageFallback = [string](Get-WinWSProfileSetting $regional 'uiLanguageFallback' '')
        UserLocale = $restoreUserLocale
        HomeLocationGeoId = $restoreHomeLocationGeoId
        SetupUserLocale = $dmaSetupUserLocale
        SetupHomeLocationGeoId = $dmaSetupHomeLocationGeoId
        DmaInterop = [pscustomobject]@{
            Enabled = $true
            SetupCountry = [string]$dmaSetupRegion.Country
            SetupUserLocale = $dmaSetupUserLocale
            SetupHomeLocationGeoId = $dmaSetupHomeLocationGeoId
            RestoreUserLocale = $restoreUserLocale
            RestoreHomeLocationGeoId = $restoreHomeLocationGeoId
            Policy = 'Always bake Windows DMA interoperability by using an EEA setup region, then restore the builder regional defaults after successful FirstLogon.'
        }
        ExportHostDrivers = $exportHostDrivers
        Editors = @($selectedEditors)
        InstallWindhawk = ($layers -contains 'windhawk')
        InstallYasb = ($layers -contains 'yasb')
        InstallKomorebi = ($layers -contains 'komorebi')
        Wsl2Distro = $wsl2Distro
        Wsl2Distros = @($wsl2Distros)
        AppxPackages = @($appxRemovalPrefixes)
        RegistryTweaks = $registryTweaks.ToArray()
        Features = $features.ToArray()
        Tweaks = [pscustomobject]@{
            DarkMode = $tweakDarkMode
            FileExtensions = $tweakFileExtensions
            StickyKeys = $tweakStickyKeys
            HardwareBypass = $tweakHardwareBypass
            UpdatePolicy = $updatePolicy
        }
        Privacy = [pscustomobject]@{
            Telemetry = $privacyTelemetry
            AdvertisingId = $privacyAdvertisingId
            Location = $privacyLocation
            Timeline = $privacyTimeline
        }
        Drivers = [pscustomobject]@{ Source = $driverSource; Path = $driverPath }
        SetupScripts = @('SetupComplete.cmd', 'SetupComplete.ps1', 'Specialize.ps1', 'DefaultUser.ps1', 'FirstLogon.ps1', 'Maintain.ps1', 'WinWSAgent', 'ViVeTool')
        Assets = @('fonts', 'cursors', 'PowerShell 7', 'winget')
        PackagesManifest = $packages
    }
}

function Get-WinWSPowerShellCachePattern {
    param([string]$Architecture)

    $suffix = switch ($Architecture) {
        'arm64' { 'win-arm64' }
        'x86' { 'win-x86' }
        default { 'win-x64' }
    }
    return "PowerShell-*-$suffix.zip"
}

function Get-WinWSViveToolCachePattern {
    param([string]$Architecture)

    if ($Architecture -eq 'arm64') {
        return @('ViVeTool-*Arm64*.zip', 'ViVeTool-*ARM64*.zip', 'ViVeTool-*arm64*.zip')
    }
    return @('ViVeTool-*IntelAmd*.zip', 'ViVeTool-*.zip')
}

function Get-WinWSOfflinePayloadCacheStatus {
    param(
        [string]$Architecture = 'amd64',
        [string]$DownloadDir = (Join-Path (Get-Win11IsoDependencyCacheRoot) 'downloads'),
        [string]$FontDir = (Join-Path (Get-WinWSRepositoryRoot) 'assets\fonts')
    )

    $missing = [System.Collections.Generic.List[string]]::new()
    $found = [ordered]@{}

    $ps7 = Get-WinWSCachedDownloadFile -DownloadDir $DownloadDir -Patterns @((Get-WinWSPowerShellCachePattern -Architecture $Architecture))
    if ($ps7) { $found['PowerShell 7'] = $ps7 } else { $missing.Add('PowerShell 7') | Out-Null }

    $vive = Get-WinWSCachedDownloadFile -DownloadDir $DownloadDir -Patterns @(Get-WinWSViveToolCachePattern -Architecture $Architecture)
    if ($vive) { $found['ViVeTool'] = $vive } else { $missing.Add('ViVeTool') | Out-Null }

    $winget = Get-WinWSCachedDownloadFile -DownloadDir $DownloadDir -Patterns @('Microsoft.DesktopAppInstaller_*.msixbundle', '*.msixbundle')
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

function Test-WinWSBuildPrerequisite {
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
    if (-not ($AllowMissingSourceIso -and $sourceIsoMissing) -and -not (Test-WinWSGitHubApiReachable -TimeoutSec 5)) {
        $cache = Get-WinWSOfflinePayloadCacheStatus -Architecture ([string]$Config.Architecture)
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
        $hint = Get-WinWSIsoArchitectureHint -Path $Config.SourceIso
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
        $windhawkBootstrap = Join-Path (Get-WinWSRepositoryRoot) 'scripts\setup\WindhawkBootstrap.ps1'
        $virtualDesktopFlyouts = Join-Path (Get-WinWSRepositoryRoot) 'scripts\setup\DisableVirtualDesktopFlyouts.ps1'
        $windhawkPreset = Join-Path (Get-WinWSRepositoryRoot) 'assets\windhawk\preset.json'
        if (-not (Test-Path -LiteralPath $windhawkBootstrap)) {
            $failures.Add("WinWS Windhawk bootstrap script is missing from the repository: $windhawkBootstrap")
        }
        if (-not (Test-Path -LiteralPath $virtualDesktopFlyouts)) {
            $failures.Add("WinWS virtual desktop flyout script is missing from the repository: $virtualDesktopFlyouts")
        }
        if (-not (Test-Path -LiteralPath $windhawkPreset)) {
            $failures.Add("WinWS Windhawk preset is missing from the repository: $windhawkPreset")
        }
    }
    if ($Config.InstallYasb) {
        foreach ($asset in @('assets\yasb\config.yaml', 'assets\yasb\styles.css')) {
            $path = Join-Path (Get-WinWSRepositoryRoot) $asset
            if (-not (Test-Path -LiteralPath $path)) {
                $failures.Add("WinWS YASB preset asset is missing from the repository: $path")
            }
        }
    }
    if ($Config.InstallKomorebi) {
        foreach ($asset in @('assets\komorebi\komorebi.json', 'assets\komorebi\applications.json', 'assets\komorebi\whkdrc')) {
            $path = Join-Path (Get-WinWSRepositoryRoot) $asset
            if (-not (Test-Path -LiteralPath $path)) {
                $failures.Add("WinWS Komorebi preset asset is missing from the repository: $path")
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

function Get-WinWSBuildOutputPathFromPipelineResult {
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

function Invoke-WinWSIsoBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [switch]$DryRun,
        [scriptblock]$ProgressHandler
    )

    Write-WinWSProgress `
        -Stage 'Start' `
        -Level Section `
        -Message 'WinWS shared build engine starting' `
        -ProgressHandler $ProgressHandler

    # Fail fast on non-elevated runs. Dry-run still inspects/mounts ISO content,
    # validates DISM/driver paths, and may follow source-prep output produced by
    # UUP Dump, so the whole build surface uses one elevation rule.
    if (-not (Test-WinWSAdministrator)) {
        Write-WinWSProgress -Stage 'Validate' -Level Error `
            -Message 'WinWS requires Administrator for builds, dry-runs, validation, source prep, and driver checks.' `
            -ProgressHandler $ProgressHandler
        throw 'Not running elevated; WinWS requires Administrator.'
    }

    $pre = Test-WinWSBuildPrerequisite -Config $Config -AllowMissingSourceIso:$DryRun
    foreach ($w in $pre.Warnings) { Write-WinWSProgress -Stage 'Validate' -Level Warn -Message $w -ProgressHandler $ProgressHandler }
    foreach ($f in $pre.Failures) { Write-WinWSProgress -Stage 'Validate' -Level Error -Message $f -ProgressHandler $ProgressHandler }
    if (-not $pre.Passed) {
        $report = New-WinWSBuildReport -Config $Config -DetectedArchitecture $Config.Architecture -Warnings $pre.Warnings -Failures $pre.Failures
        $paths = Save-WinWSBuildReport -Report $report
        throw "Build prerequisites failed. Report: $($paths.Json)"
    }

    $sourceIsoAvailable = -not [string]::IsNullOrWhiteSpace($Config.SourceIso) -and (Test-Path -LiteralPath $Config.SourceIso)
    $detected = if ($sourceIsoAvailable) { Get-WinWSIsoArchitectureHint -Path $Config.SourceIso } else { $null }
    if (-not $detected) { $detected = $Config.Architecture }
    $sourceMessage = if ($sourceIsoAvailable) {
        "Source ISO found; architecture hint: $detected"
    }
    else {
        "Dry run architecture: $detected"
    }
    Write-WinWSProgress `
        -Stage 'Validate' `
        -Level OK `
        -Message $sourceMessage `
        -ProgressHandler $ProgressHandler
    Write-WinWSProgress `
        -Stage 'Profile' `
        -Level OK `
        -Message "Profile: $($Config.Profile); editors: $($Config.Editors -join ', ')" `
        -ProgressHandler $ProgressHandler

    $report = New-WinWSBuildReport -Config $Config -DetectedArchitecture $detected -Warnings $pre.Warnings
    $paths = Save-WinWSBuildReport -Report $report
    Write-WinWSProgress -Stage 'Report' -Level OK -Message "Wrote $($paths.Json)" -ProgressHandler $ProgressHandler
    Initialize-WinWSBuildManifest -Config $Config
    if ($DryRun -and -not $sourceIsoAvailable) {
        Write-WinWSProgress `
            -Stage 'DryRun' `
            -Level OK `
            -Message 'Profile-only dry run completed. Provide an ISO to generate autounattend and setup artifacts.' `
            -ProgressHandler $ProgressHandler
        $manifestPath = Save-WinWSBuildManifest -OutputDir (Get-WinWSOutputDirectory) -DryRun
        if ($manifestPath) {
            Write-WinWSProgress -Stage 'Report' -Level OK -Message "Wrote $manifestPath" -ProgressHandler $ProgressHandler
        }
        return [pscustomobject]@{ Report = $report; Paths = $paths; OutputPath = (Get-WinWSOutputDirectory) }
    }
    if (Get-Command Invoke-WinWSIsoPipeline -ErrorAction SilentlyContinue) {
        $stage = if ($DryRun) { 'DryRun' } else { 'Build' }
        Write-WinWSProgress `
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
        $previousProgressVariable = Get-Variable -Name WinWSProgressHandler -Scope Script -ErrorAction SilentlyContinue
        if ($previousProgressVariable) {
            $hadPreviousProgressHandler = $true
            $previousProgressHandler = $previousProgressVariable.Value
        }
        try {
            if ($ProgressHandler) {
                $script:WinWSProgressHandler = $ProgressHandler
            }
            $pipeline = Invoke-WinWSIsoPipeline `
                -BuildConfig $Config `
                -DryRun:$DryRun `
                -ExportHostDrivers:$Config.ExportHostDrivers
            $pipelineOutputIso = Get-WinWSBuildOutputPathFromPipelineResult -PipelineResult $pipeline -FallbackPath ''
            try {
                $manifestPath = Save-WinWSBuildManifest `
                    -OutputDir (Get-WinWSOutputDirectory) `
                    -OutputIsoPath $pipelineOutputIso `
                    -DryRun:$DryRun
                if ($manifestPath) {
                    Write-WinWSProgress -Stage 'Report' -Level OK -Message "Wrote $manifestPath" -ProgressHandler $ProgressHandler
                }
            }
            catch {
                $manifestError = $_
                $isoExists = -not [string]::IsNullOrWhiteSpace($pipelineOutputIso) -and (Test-Path -LiteralPath $pipelineOutputIso)
                if (-not $isoExists -and -not $DryRun) { throw }
                Write-WinWSProgress `
                    -Stage 'Report' `
                    -Level Warn `
                    -Message "Build output completed, but manifest save failed: $($manifestError.Exception.Message)" `
                    -ProgressHandler $ProgressHandler
            }
        }
        catch {
            Save-WinWSBuildManifest -OutputDir (Get-WinWSOutputDirectory) -Failed | Out-Null
            throw
        }
        finally {
            if ($hadPreviousProgressHandler) {
                $script:WinWSProgressHandler = $previousProgressHandler
            } else {
                Remove-Variable -Name WinWSProgressHandler -Scope Script -ErrorAction SilentlyContinue
            }
        }
        $resultPath = Get-WinWSBuildOutputPathFromPipelineResult -PipelineResult $pipeline -FallbackPath (Get-WinWSOutputDirectory)
    }
    else {
        $resultPath = Get-WinWSOutputDirectory
        Write-WinWSProgress `
            -Stage 'Build' `
            -Level Warn `
            -Message 'ISO pipeline is not loaded; reports only.' `
            -ProgressHandler $ProgressHandler
    }
    return [pscustomobject]@{ Report = $report; Paths = $paths; OutputPath = $resultPath }
}

Set-Alias -Name Test-WinWSBuildPrerequisites -Value Test-WinWSBuildPrerequisite

function Start-WinWSBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$BuildProfile,
        [switch]$DryRun,
        [scriptblock]$ProgressHandler
    )

    $config = New-WinWSBuildConfig -BuildProfile $BuildProfile

    try {
        # Strip ALL password / auto-logon state from the public artifact so it
        # round-trips through -ResumeProfile as a passwordless profile. Leaving
        # passwordSet=true while clearing the secret tripped Test-WinWSBuild-
        # Prerequisite ("passwordSet is true but passwordIncluded is false")
        # and made the published artifact unusable as a resume input.
        $pubProfile = $BuildProfile | ConvertTo-Json -Depth 16 | ConvertFrom-Json
        $pubProfile.identity.PSObject.Properties.Remove('password')
        $pubProfile.identity.passwordIncluded = $false
        $pubProfile.identity.passwordSet = $false
        $pubProfile.identity.autoLogon = $false
        $artifactPath = Join-Path (Get-WinWSOutputDirectory) 'WinWS-BuildProfile.json'
        $null = Save-WinWSBuildProfile -BuildProfile $pubProfile -Path $artifactPath
        Write-WinWSProgress -Stage 'Profile' -Level OK -Message "Build profile: $artifactPath" -ProgressHandler $ProgressHandler
    }
    catch {
        Write-WinWSProgress -Stage 'Profile' -Level Warn -Message "Could not save profile artifact: $_" -ProgressHandler $ProgressHandler
    }

    Invoke-WinWSIsoBuild -Config $config -DryRun:$DryRun -ProgressHandler $ProgressHandler
}
