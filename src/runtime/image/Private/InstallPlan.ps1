#Requires -Version 7.6

function New-WinMintInstallPlanDiagnosticsBlock {
    param([Parameter(Mandatory)]$BuildConfig)

    [ordered]@{
        retainFirstLogonArtifacts = [bool]$BuildConfig.Diagnostics.RetainFirstLogonArtifacts
        provisioningShellDwellMs = [int]$BuildConfig.Diagnostics.ProvisioningShellDwellMs
        wslRuntimeValidation = [string]$BuildConfig.Diagnostics.WslRuntimeValidation
        vmGuestBasicConsole = [bool]$BuildConfig.Diagnostics.VmGuestBasicConsole
    }
}

function New-WinMintInstallPlanAgentProfile {
    param([Parameter(Mandatory)]$BuildConfig)

    $wslSelection = ConvertTo-WinMintWslSelection `
        -Values @($BuildConfig.Wsl2Distros) `
        -FallbackValues @($BuildConfig.Wsl2Distro)
    $wslDistros = @($wslSelection.AgentTokens)
    $wslDistro = [string]$wslSelection.AgentToken
    $dotfilesEnabled = $false
    $dotfilesRepository = ''
    $dotfilesRef = 'main'
    $dotfilesInstallScript = ''
    if ($BuildConfig.Dotfiles) {
        $dotfilesEnabled = [bool]$BuildConfig.Dotfiles.Enabled
        $dotfilesRepository = [string]$BuildConfig.Dotfiles.Repository
        $dotfilesRef = [string]$BuildConfig.Dotfiles.Ref
        if ([string]::IsNullOrWhiteSpace($dotfilesRef)) { $dotfilesRef = 'main' }
        $dotfilesInstallScript = [string]$BuildConfig.Dotfiles.InstallScript
    }
    # Package-manager bootstrap is baseline: Scoop + MinGit are developer
    # plumbing, and winget remains the owner for selected GUI/system tools.
    $needsPackageManagers = $true
    $needsRaycast = [bool]$BuildConfig.InstallRaycast
    $launcherKeyTarget = if ($needsRaycast) { 'Raycast' } else { 'Search' }
    $everythingPackage = if ([string]$BuildConfig.Architecture -eq 'arm64') { 'everything-arm64-beta' } else { 'everything-beta' }
    $raycastExtensions = [System.Collections.Generic.List[object]]::new()
    if ($needsRaycast) {
        $raycastExtensions.Add([ordered]@{ id = 'everything-search'; owner = 'anastasiy_safari'; source = 'Raycast Store'; requires = @($everythingPackage) }) | Out-Null
        $raycastExtensions.Add([ordered]@{ id = 'windows-terminal'; owner = 'lunaris'; source = 'Raycast Store'; requires = @() }) | Out-Null
        if ([bool]$BuildConfig.InstallThide) {
            $raycastExtensions.Add([ordered]@{ id = 'window-walker'; owner = 'nazzy_wazzy_lu'; source = 'Raycast Store'; requires = @() }) | Out-Null
        }
        if (@($BuildConfig.Editors) -contains 'vscode') {
            $raycastExtensions.Add([ordered]@{ id = 'visual-studio-code'; owner = 'thomas'; source = 'Raycast Store'; requires = @() }) | Out-Null
        }
        if (@($BuildConfig.Editors) -contains 'zed') {
            $raycastExtensions.Add([ordered]@{ id = 'zed-recent-projects'; owner = 'ewgenius'; source = 'Raycast Store'; requires = @() }) | Out-Null
        }
        if (@($BuildConfig.Browsers) -contains 'zen-browser') {
            $raycastExtensions.Add([ordered]@{ id = 'zen-browser'; owner = 'Keyruu'; source = 'Raycast Store'; requires = @() }) | Out-Null
        }
    }
    [ordered]@{
        profile = [string]$BuildConfig.Profile
        diagnostics = New-WinMintInstallPlanDiagnosticsBlock -BuildConfig $BuildConfig
        targetArchitecture = [string]$BuildConfig.Architecture
        editors = @($BuildConfig.Editors)
        browsers = @($BuildConfig.Browsers)
        modules = [ordered]@{
            packageManagers = [ordered]@{ enabled = $needsPackageManagers }
            git = [ordered]@{
                enabled = $false
                defaultBranch = 'main'
                credentialHelper = 'manager'
            }
            dotfiles = [ordered]@{
                enabled = $dotfilesEnabled
                repository = $dotfilesRepository
                ref = $dotfilesRef
                installScript = $dotfilesInstallScript
            }
            wsl = [ordered]@{
                # WSL2 is baseline. The agent stays enabled even when no
                # distro is selected so it can lay down .wslconfig and set the
                # default version to 2.
                enabled = $true
                distro = $wslDistro
                distros = @($wslDistros)
            }
            # Optional command launcher.
            raycast = [ordered]@{
                enabled = $needsRaycast
                extensions = @($raycastExtensions.ToArray())
                everythingBackend = [ordered]@{
                    enabled = $needsRaycast
                    package = $everythingPackage
                    localFilesystemOnly = $true
                    trayIcon = 'hidden'
                    serverSearch = 'disabled'
                    sdkSearch = 'disabled'
                }
            }
            launcherKey = [ordered]@{
                enabled = $true
                target = $launcherKeyTarget
                chord = 'Win+Shift+F23'
            }
            browsers = [ordered]@{ enabled = (@($BuildConfig.Browsers).Count -gt 0) }
            liveInstallAudit = [ordered]@{ enabled = [bool]$BuildConfig.LiveInstallAudit }
            phoneLink = [ordered]@{
                enabled = [bool]$BuildConfig.PhoneLink
                showInFileExplorer = [bool]$BuildConfig.PhoneLink
                crossDeviceCopyPaste = [bool]$BuildConfig.PhoneLink
                hideCrossDeviceHomeFolder = [bool]$BuildConfig.PhoneLink
            }
            shell = [ordered]@{
                komorebi = [bool]$BuildConfig.InstallKomorebi
                yasb = [bool]$BuildConfig.InstallYasb
                thide = [bool]$BuildConfig.InstallThide
                whkd = [bool]$BuildConfig.InstallKomorebi
                nilesoft = [bool]$BuildConfig.InstallNilesoft
            }
            windhawk = [ordered]@{ enabled = [bool]$BuildConfig.InstallWindhawk }
        }
    }
}

function New-WinMintInstallPlanSetupProfile {
    param([Parameter(Mandatory)]$BuildConfig)

    $removeEdgeBrowser = (-not [bool]$BuildConfig.Keep.Edge)
    $appxSystemExemptPrefixes = @()
    if ($BuildConfig.PSObject.Properties['AppxSystemExemptPrefixes']) {
        $appxSystemExemptPrefixes = @($BuildConfig.AppxSystemExemptPrefixes)
    }

    [ordered]@{
        schemaVersion = 2
        profile = [string]$BuildConfig.Profile
        diagnostics = New-WinMintInstallPlanDiagnosticsBlock -BuildConfig $BuildConfig
        # FirstLogon re-establishes the FULL autologon (user + password) before every
        # install reboot so auto sign-in never breaks mid-install, and wipes it (and this
        # staged secret, via the residual cleanup) once setup completes. The plaintext
        # password is an intentional, bounded local-machine secret for a hands-off install.
        account = [ordered]@{
            userName = [string]$BuildConfig.AccountName
            accountMode = [string]$BuildConfig.AccountMode
            autoLogon = [bool]$BuildConfig.AutoLogon
            password = [string]$BuildConfig.Password
        }
        appxRemovalPrefixes = @($BuildConfig.AppxPackages)
        appxSystemExemptPrefixes = @($appxSystemExemptPrefixes)
        appxCatalogVersion = [int]$BuildConfig.AppxCatalogVersion
        registryTweaks = @($BuildConfig.RegistryTweaks)
        windowsFeatures = @($BuildConfig.Features)
        defaultUser = [ordered]@{
            darkMode = [bool]$BuildConfig.Tweaks.DarkMode
            stickyKeysOff = [bool]$BuildConfig.Tweaks.StickyKeysOff
            advertisingIdDisabled = [bool]$BuildConfig.Privacy.AdvertisingIdDisabled
        }
        setupComplete = [ordered]@{
            preserveWindowsUpdate = ([string]$BuildConfig.Tweaks.UpdatePolicy -eq 'All')
            removeRecall = $true
        }
        aiRemoval = [ordered]@{
            policy = [string]$BuildConfig.AiRemoval.Policy
            catalogVersion = [int]$BuildConfig.AiRemoval.CatalogVersion
            appxPrefixes = @($BuildConfig.AiRemoval.AppxPrefixes)
            removeRecall = $true
            disableAiServices = (@($BuildConfig.AiRemoval.ServicesToDisable).Count -gt 0)
            disableAiTasks = $true
            aggressiveExperimental = [bool]$BuildConfig.AiRemoval.AggressiveExperimental
            optionalFeatures = @($BuildConfig.AiRemoval.OptionalFeatures)
            servicesToDisable = @($BuildConfig.AiRemoval.ServicesToDisable)
            scheduledTaskPatternsToDisable = @($BuildConfig.AiRemoval.ScheduledTaskPatternsToDisable)
        }
        windowsPolicy = [ordered]@{
            dualBoot = ([string]$BuildConfig.DiskMode -eq 'DualBootReserved')
            disableFastStartup = ([string]$BuildConfig.DiskMode -eq 'DualBootReserved')
            preventDeviceEncryption = ([string]$BuildConfig.DiskMode -eq 'DualBootReserved')
            disableWpbtExecution = $true
            realTimeIsUniversal = ([string]$BuildConfig.DiskMode -eq 'DualBootReserved')
            primaryAssumption = [string]$BuildConfig.PrimaryAssumption
        }
        regional = [ordered]@{
            timeZoneId = [string]$BuildConfig.TimeZoneId
            # Resolved secondary input languages (keyboards) FirstLogon adds to the user list
            # while keeping en-US as the display language. Empty = none.
            secondaryInputLanguages = @($BuildConfig.SecondaryInputLanguages)
            dmaInterop = [ordered]@{
                enabled = [bool]$BuildConfig.DmaInterop.Enabled
                setupCountry = [string]$BuildConfig.DmaInterop.SetupCountry
                setupUserLocale = [string]$BuildConfig.SetupUserLocale
                setupHomeLocationGeoId = [int]$BuildConfig.SetupHomeLocationGeoId
                restoreTimeZoneId = [string]$BuildConfig.TimeZoneId
                restoreUiLanguage = [string]$BuildConfig.UiLanguage
                restoreUserLocale = [string]$BuildConfig.UserLocale
                restoreHomeLocationGeoId = [int]$BuildConfig.HomeLocationGeoId
                restoreLocationServices = [bool]$BuildConfig.DmaInterop.RestoreLocationServices
            }
        }
        privacy = [ordered]@{
            telemetryHardening = [bool]$BuildConfig.Privacy.TelemetryHardening
            advertisingIdDisabled = [bool]$BuildConfig.Privacy.AdvertisingIdDisabled
            location = [bool]$BuildConfig.Privacy.Location
            activityHistoryDisabled = [bool]$BuildConfig.Privacy.ActivityHistoryDisabled
            disableTelemetryTasks = [bool]$BuildConfig.Privacy.TelemetryHardening
            telemetryTaskPatternsToDisable = @($BuildConfig.TelemetryTaskPatterns)
        }
        power = [ordered]@{
            formFactor = [string]$BuildConfig.FormFactor
            dualBoot = ([string]$BuildConfig.DiskMode -eq 'DualBootReserved')
            disableHibernationOnDesktop = $true
            desktopPowerPlan = [string]$BuildConfig.PowerPlan
            selectedPlan = [string]$BuildConfig.PowerPlan
        }
        edge = [ordered]@{
            # Edge removal intent is serviced by SetupComplete through the normal
            # supported app uninstaller. WebView2 / Edge runtime infrastructure is
            # preserved.
            removeEdge = $removeEdgeBrowser
            keepEdge = [bool]$BuildConfig.Keep.Edge
            dmaInteropEnabled = [bool]$BuildConfig.DmaInterop.Enabled
        }
    }
}

function New-WinMintInstallPlanSetupPlan {
    param(
        [Parameter(Mandatory)]$BuildConfig,
        [Parameter(Mandatory)]$SetupProfile,
        [Parameter(Mandatory)]$AgentProfile
    )

    $diskMode = [string]$BuildConfig.DiskMode
    $accountMode = [string]$BuildConfig.AccountMode
    $firstLogonModules = [System.Collections.Generic.List[string]]::new()
    $moduleNames = if ($AgentProfile.modules -is [System.Collections.IDictionary]) {
        @($AgentProfile.modules.Keys | ForEach-Object { [string]$_ })
    }
    else {
        @($AgentProfile.modules.PSObject.Properties.Name | ForEach-Object { [string]$_ })
    }
    foreach ($module in $moduleNames) {
        $value = if ($AgentProfile.modules -is [System.Collections.IDictionary]) {
            $AgentProfile.modules[$module]
        }
        else {
            $AgentProfile.modules.$module
        }
        $enabled = $false
        if ($value -is [bool]) {
            $enabled = [bool]$value
        }
        elseif ($value -is [System.Collections.IDictionary] -and $value.Contains('enabled')) {
            $enabled = [bool]$value['enabled']
        }
        elseif ($value -and $value.PSObject.Properties['enabled']) {
            $enabled = [bool]$value.enabled
        }
        elseif ($module -eq 'shell' -and $value) {
            if ($value -is [System.Collections.IDictionary]) {
                $enabled = [bool]$value['komorebi'] -or [bool]$value['yasb'] -or [bool]$value['thide'] -or [bool]$value['whkd'] -or [bool]$value['nilesoft']
            }
            else {
                $enabled = [bool]$value.komorebi -or [bool]$value.yasb -or [bool]$value.thide -or [bool]$value.whkd -or [bool]$value.nilesoft
            }
        }
        if ($enabled) { $firstLogonModules.Add($module) | Out-Null }
    }
    if (@($BuildConfig.Editors).Count -gt 0) { $firstLogonModules.Add('editors') | Out-Null }
    if (@($BuildConfig.Browsers).Count -gt 0) { $firstLogonModules.Add('browsers') | Out-Null }

    [ordered]@{
        schemaVersion = 2
        profile = [string]$BuildConfig.Profile
        generatedBy = 'WinMint backend'
        accountMode = $accountMode
        editionMode = [string]$BuildConfig.EditionMode
        diskMode = $diskMode
        phases = @(
            [ordered]@{
                id = 'windowsPE'
                context = 'Windows PE'
                entrypoint = 'autounattend.xml RunSynchronous'
                responsibilities = @(
                    'apply optional hardware compatibility bypass',
                    'prepare disk layout when automated disk mode is selected',
                    'hand Windows Setup the selected edition policy'
                )
            }
            [ordered]@{
                id = 'specialize'
                context = 'SYSTEM before first user'
                entrypoint = 'C:\Windows\Setup\Scripts\Specialize.ps1'
                responsibilities = @(
                    'apply machine policy that must exist before OOBE',
                    'load setup profile from WinMintSetupProfile.json'
                )
            }
            [ordered]@{
                id = 'setupComplete'
                context = 'SYSTEM after Windows Setup'
                entrypoint = 'C:\Windows\Setup\Scripts\SetupComplete.cmd'
                responsibilities = @(
                    'run SetupComplete.ps1',
                    'finish machine-level cleanup',
                    'keep Windows Update and serviceability infrastructure intact'
                )
            }
            [ordered]@{
                id = 'defaultUser'
                context = 'Default user registry hive'
                entrypoint = 'C:\Windows\Setup\Scripts\DefaultUser.ps1'
                responsibilities = @(
                    'apply HKCU defaults for newly-created users',
                    'keep known folders local',
                    'remove default-user first-run pressure'
                )
            }
            [ordered]@{
                id = 'firstLogon'
                context = 'Live user at first sign-in'
                entrypoint = 'C:\Windows\Setup\Scripts\FirstLogon.ps1'
                responsibilities = @(
                    'clear autologon residue',
                    'run WinMintAgent',
                    'write retry/audit state',
                    'finish live-user package and shell setup'
                )
            }
        )
        stagedArtifacts = @(
            'autounattend.xml'
            Get-WinMintSetupPayloadRequiredArtifacts -LiveInstallAudit ([bool]$BuildConfig.LiveInstallAudit)
        )
        generatedProfiles = [ordered]@{
            setupProfile = $SetupProfile
            agentProfile = $AgentProfile
        }
        firstLogon = [ordered]@{
            modules = @($firstLogonModules | Select-Object -Unique)
            editors = @($BuildConfig.Editors)
            wslDistros = @($BuildConfig.Wsl2Distros)
        }
        notes = @(
            'UI and CLI must treat this plan as backend output; neither should duplicate setup-phase business logic.',
            $(if ([bool]$BuildConfig.DmaInterop.Enabled) {
                    'Windows setup uses an EEA region for opt-in DMA interoperability, then FirstLogon restores the configured regional defaults and location-services posture.'
                } else {
                    'DMA interoperability setup-region override is disabled; setup uses the configured regional defaults.'
                }),
            'OneDrive is not offered or auto-provisioned by default; manual reinstall remains possible after setup.'
        )
    }
}

function New-WinMintInstallPlanFromBuildConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$BuildConfig
    )

    $setupProfile = New-WinMintInstallPlanSetupProfile -BuildConfig $BuildConfig
    $agentProfile = New-WinMintInstallPlanAgentProfile -BuildConfig $BuildConfig
    $wslSelection = ConvertTo-WinMintWslSelection `
        -Values @($BuildConfig.Wsl2Distros) `
        -FallbackValues @($BuildConfig.Wsl2Distro)
    $setupPlan = New-WinMintInstallPlanSetupPlan `
        -BuildConfig $BuildConfig `
        -SetupProfile $setupProfile `
        -AgentProfile $agentProfile

    [pscustomobject]@{
        BuildConfig = $BuildConfig
        SetupProfile = $setupProfile
        AgentProfile = $agentProfile
        SetupPlan = $setupPlan
        Facts = [ordered]@{
            profile = [string]$BuildConfig.Profile
            keep = [ordered]@{
                edge = [bool]$BuildConfig.Keep.Edge
                gaming = [bool]$BuildConfig.Keep.Gaming
                copilot = [bool]$BuildConfig.Keep.Copilot
            }
            regional = [ordered]@{
                dmaInterop = [bool]$BuildConfig.DmaInterop.Enabled
                setupCountry = [string]$BuildConfig.DmaInterop.SetupCountry
                setupUserLocale = [string]$BuildConfig.SetupUserLocale
                setupHomeLocationGeoId = [int]$BuildConfig.SetupHomeLocationGeoId
                restoreTimeZoneId = [string]$BuildConfig.TimeZoneId
                restoreUiLanguage = [string]$BuildConfig.UiLanguage
                restoreUserLocale = [string]$BuildConfig.UserLocale
                restoreHomeLocationGeoId = [int]$BuildConfig.HomeLocationGeoId
                restoreLocationServices = [bool]$BuildConfig.DmaInterop.RestoreLocationServices
                locationServicesPolicy = if ([bool]$BuildConfig.Privacy.Location) { 'enabled' } else { 'disabled' }
            }
            removals = [ordered]@{
                appxPrefixes = @($BuildConfig.AppxPackages)
                appxCatalogVersion = [int]$BuildConfig.AppxCatalogVersion
                featuresEnabled = @($BuildConfig.Features)
                aiPolicy = [string]$BuildConfig.AiRemoval.Policy
                aiCatalogVersion = [int]$BuildConfig.AiRemoval.CatalogVersion
                aiAppxPrefixes = @($BuildConfig.AiRemoval.AppxPrefixes)
                aiOptionalFeatures = @($BuildConfig.AiRemoval.OptionalFeatures)
                aiRegistryPolicies = @(
                    @($BuildConfig.RegistryTweaks) |
                        Where-Object { $_ -in @('windows-ai-core-policy', 'windows-ai-full-policy') }
                )
                aiAggressiveActions = @(
                    if ([bool]$BuildConfig.AiRemoval.AggressiveExperimental) {
                        @($BuildConfig.AiRemoval.AggressiveExperimentalPatterns)
                    }
                )
                removeEdge = [bool]$setupProfile.edge.removeEdge
                keepEdge = [bool]$setupProfile.edge.keepEdge
            }
            setup = [ordered]@{
                accountMode = [string]$BuildConfig.AccountMode
                diskMode = [string]$BuildConfig.DiskMode
                editionMode = [string]$BuildConfig.EditionMode
                edition = [string]$BuildConfig.Edition
                autoWipeDisk = [bool]$BuildConfig.AutoWipeDisk
                localAccountPasswordIncluded = ([string]$BuildConfig.AccountMode -eq 'Local' -and -not [string]::IsNullOrWhiteSpace([string]$BuildConfig.Password))
            }
            firstLogon = [ordered]@{
                modules = @($setupPlan.firstLogon.modules)
                editors = @($BuildConfig.Editors)
                browsers = @($BuildConfig.Browsers)
                wslDistros = @($wslSelection.ProfileTokens)
                wslAgentDistros = @($wslSelection.AgentTokens)
                wslSelections = @($wslSelection.Items)
                launcher = [string]$BuildConfig.Launcher
                shellLayers = @(
                    if ([bool]$BuildConfig.InstallWindhawk) { 'windhawk' }
                    if ([bool]$BuildConfig.InstallYasb) { 'yasb' }
                    if ([bool]$BuildConfig.InstallThide) { 'thide' }
                    if ([bool]$BuildConfig.InstallKomorebi) { 'komorebi' }
                    if ([bool]$BuildConfig.InstallNilesoft) { 'nilesoft' }
                )
            }
            artifacts = [ordered]@{
                setupProfile = 'WinMintSetupProfile.json'
                agentProfile = 'WinMintAgentProfile.json'
                setupPlan = 'WinMintSetupPlan.json'
            }
        }
    }
}

function New-WinMintInstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$BuildProfile
    )

    $buildConfig = New-WinMintBuildConfig -BuildProfile $BuildProfile
    New-WinMintInstallPlanFromBuildConfig -BuildConfig $buildConfig
}

function Get-WinMintInstallPlanForBuildConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$BuildConfig,
        [AllowNull()]$ExistingPlan
    )

    if ($null -ne $ExistingPlan -and
        $ExistingPlan.PSObject.Properties['BuildConfig'] -and
        $ExistingPlan.PSObject.Properties['SetupProfile'] -and
        $ExistingPlan.PSObject.Properties['AgentProfile'] -and
        $ExistingPlan.PSObject.Properties['SetupPlan']) {
        return $ExistingPlan
    }

    New-WinMintInstallPlanFromBuildConfig -BuildConfig $BuildConfig
}

