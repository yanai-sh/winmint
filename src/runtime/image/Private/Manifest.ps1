#Requires -Version 7.3

$script:WinMintBuildManifest = $null

function Get-WinMintBuildManifest {
    [CmdletBinding()]
    param()

    if ($null -eq $script:WinMintBuildManifest) { return $null }
    $script:WinMintBuildManifest | ConvertTo-Json -Depth 32 | ConvertFrom-Json
}

function Clear-WinMintBuildManifest {
    [CmdletBinding()]
    param()

    $script:WinMintBuildManifest = $null
}

function Test-WinMintBuildManifestInitialized {
    [CmdletBinding()]
    param()

    return ($null -ne $script:WinMintBuildManifest)
}

function Set-WinMintManifestWingetConfigurationFact {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$PackageCount
    )

    if ($null -eq $script:WinMintBuildManifest) { return }
    $script:WinMintBuildManifest.firstLogon['wingetConfigurationPath'] = $Path
    $script:WinMintBuildManifest.firstLogon['wingetConfigurationPackageCount'] = $PackageCount
}

function Get-WinMintRegistryTweakGroupValue {
    param(
        [Parameter(Mandatory)]$Group,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($Group -is [System.Collections.IDictionary]) {
        if ($Group.ContainsKey($Name)) { return $Group[$Name] }
        return $Default
    }

    $property = $Group.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function ConvertTo-WinMintRegistryAuditPath {
    param([Parameter(Mandatory)][string]$Path)

    switch -Regex ($Path) {
        '^zSOFTWARE\\(.+)$' { return "HKEY_LOCAL_MACHINE\SOFTWARE\$($Matches[1])" }
        '^zSYSTEM\\(.+)$' { return "HKEY_LOCAL_MACHINE\SYSTEM\$($Matches[1])" }
        '^zDEFAULT\\(.+)$' { return "HKEY_USERS\.DEFAULT\$($Matches[1])" }
        '^zNTUSER\\(.+)$' { return "HKEY_USERS\.DEFAULT\$($Matches[1])" }
        default { return $Path }
    }
}

function ConvertTo-WinMintRegDwordText {
    param([Parameter(Mandatory)][string]$Value)

    $number = 0
    if ([int64]::TryParse($Value, [ref]$number)) {
        return ('dword:{0:x8}' -f $number)
    }
    return ('dword:{0:x8}' -f 0)
}

function ConvertTo-WinMintRegStringText {
    param([AllowNull()][string]$Value)

    $escaped = ([string]$Value) -replace '"', '\"'
    return '"' + $escaped + '"'
}

function ConvertTo-WinMintRegValueLine {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Type,
        [AllowNull()][string]$Value
    )

    $regName = if ([string]::IsNullOrWhiteSpace($Name)) { '@' } else { ConvertTo-WinMintRegStringText -Value $Name }
    $regValue = switch ($Type) {
        'REG_DWORD' { ConvertTo-WinMintRegDwordText -Value ([string]$Value) }
        default { ConvertTo-WinMintRegStringText -Value ([string]$Value) }
    }
    return "$regName=$regValue"
}

function New-WinMintRegistryTweakDetail {
    param(
        [Parameter(Mandatory)]$Group,
        [string]$Status = 'pending',
        [string]$ErrorMessage = ''
    )

    $setOps = @(Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'set' -Default @())
    $removeOps = @(Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'remove' -Default @())
    $rollbackCount = @(
        foreach ($entry in $setOps) {
            if ($null -ne (Get-WinMintRegistryTweakGroupValue -Group $entry -Name 'undo')) { $entry }
        }
        foreach ($entry in $removeOps) {
            if ($null -ne (Get-WinMintRegistryTweakGroupValue -Group $entry -Name 'restore')) { $entry }
        }
    ).Count

    [ordered]@{
        id = [string](Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'id')
        description = [string](Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'description')
        scope = [string](Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'scope' -Default 'offline registry')
        risk = [string](Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'risk' -Default 'low')
        reversible = [bool](Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'reversible' -Default $false)
        phase = [string](Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'phase' -Default 'offline-image')
        intent = [string](Get-WinMintRegistryTweakGroupValue -Group $Group -Name 'intent' -Default '')
        status = $Status
        setOperations = $setOps.Count
        removeOperations = $removeOps.Count
        rollbackOperations = $rollbackCount
        rollbackCoverage = if (($setOps.Count + $removeOps.Count) -eq 0) {
            'none'
        } elseif ($rollbackCount -eq 0) {
            'none'
        } elseif ($rollbackCount -eq ($setOps.Count + $removeOps.Count)) {
            'full'
        } else {
            'partial'
        }
        error = $ErrorMessage
    }
}

function Get-WinMintManifestInstallPlanFacts {
    param(
        [Parameter(Mandatory)]$Config,
        [AllowNull()]$InstallPlan
    )

    if ($null -ne $InstallPlan -and $InstallPlan.PSObject.Properties['Facts']) {
        return $InstallPlan.Facts
    }

    $layers = @(
        if ($Config.InstallWindhawk) { 'windhawk' }
        if ($Config.InstallYasb) { 'yasb' }
        if ($Config.InstallThide) { 'thide' }
        if ($Config.InstallKomorebi) { 'komorebi' }
        if ($Config.InstallNilesoft) { 'nilesoft' }
    )

    [ordered]@{
        regional = [ordered]@{
            dmaInterop = [bool]$Config.DmaInterop.Enabled
            setupCountry = [string]$Config.DmaInterop.SetupCountry
            setupUserLocale = [string]$Config.SetupUserLocale
            setupHomeLocationGeoId = [int]$Config.SetupHomeLocationGeoId
            restoreTimeZoneId = [string]$Config.TimeZoneId
            restoreUserLocale = [string]$Config.UserLocale
            restoreHomeLocationGeoId = [int]$Config.HomeLocationGeoId
            restoreLocationServices = [bool]$Config.DmaInterop.RestoreLocationServices
            locationServicesPolicy = if ([bool]$Config.Privacy.Location) { 'enabled' } else { 'disabled' }
        }
        removals = [ordered]@{
            appxPrefixes = @($Config.AppxPackages)
            appxCatalogVersion = [int]$Config.AppxCatalogVersion
            featuresEnabled = @($Config.Features)
            aiPolicy = [string]$Config.AiRemoval.Policy
            aiCatalogVersion = [int]$Config.AiRemoval.CatalogVersion
            aiAppxPrefixes = @($Config.AiRemoval.AppxPrefixes)
            aiRegistryPolicies = @(
                @($Config.RegistryTweaks) |
                    Where-Object { $_ -in @('windows-ai-core-policy', 'windows-ai-full-policy') }
            )
            aiAggressiveActions = @(
                if ([bool]$Config.AiRemoval.AggressiveExperimental) {
                    @($Config.AiRemoval.AggressiveExperimentalPatterns)
                }
            )
            removeEdge = (-not [bool]$Config.Keep.Edge)
            keepEdge = [bool]$Config.Keep.Edge
        }
        firstLogon = [ordered]@{
            editors = @($Config.Editors)
            wslDistros = @($Config.Wsl2Distros)
            shellLayers = @($layers)
        }
    }
}

function Initialize-WinMintBuildManifest {
    param(
        [Parameter(Mandatory)]$Config,
        [AllowNull()]$InstallPlan = $null
    )

    $planFacts = Get-WinMintManifestInstallPlanFacts -Config $Config -InstallPlan $InstallPlan

    $script:WinMintBuildManifest = [ordered]@{
        schemaVersion       = 2
        builtAt             = [DateTimeOffset]::Now.ToString('o')
        buildDurationSeconds = $null
        buildResult         = 'pending'
        source              = [ordered]@{
            isoPath      = [string]$Config.SourceIso
            architecture = [string]$Config.Architecture
            editions     = @()
        }
        target              = [ordered]@{
            diskMode   = [string]$Config.DiskMode
            diskLayout = $Config.DiskLayout
            primaryAssumption = [string]$Config.PrimaryAssumption
        }
        regional            = [ordered]@{
            timeZoneId = [string]$Config.TimeZoneId
            uiLanguage = [string]$Config.UILanguage
            systemLocale = [string]$Config.SystemLocale
            userLocale = [string]$Config.UserLocale
            inputLocale = [string]$Config.InputLocale
            homeLocationGeoId = [int]$Config.HomeLocationGeoId
            dmaInterop = [ordered]@{
                enabled = [bool]$Config.DmaInterop.Enabled
                defaultEnabled = $true
                setupCountry = [string]$planFacts.regional.setupCountry
                setupUserLocale = [string]$planFacts.regional.setupUserLocale
                setupHomeLocationGeoId = [int]$planFacts.regional.setupHomeLocationGeoId
                setupLatchedCountry = [string]$planFacts.regional.setupCountry
                setupLatchedGeoId = [int]$planFacts.regional.setupHomeLocationGeoId
                restoreUserLocale = [string]$planFacts.regional.restoreUserLocale
                restoreHomeLocationGeoId = [int]$planFacts.regional.restoreHomeLocationGeoId
                restoredUserLocale = [string]$planFacts.regional.restoreUserLocale
                restoredHomeLocationGeoId = [int]$planFacts.regional.restoreHomeLocationGeoId
                restoredTimeZoneId = [string]$planFacts.regional.restoreTimeZoneId
                locationServicesPolicy = [string]$planFacts.regional.locationServicesPolicy
            }
        }
        removals            = [ordered]@{
            appxPrefixes        = @($planFacts.removals.appxPrefixes)
            appxCatalogVersion  = [int]$planFacts.removals.appxCatalogVersion
            appxRemoved         = @()
            appxRemovedCount    = 0
            capabilitiesRemoved = @()
            windowsPackagesRemoved = @()
            languagePackagesRemoved = @()
            languagePackagesRemovedCount = 0
            oobeRehydration = [ordered]@{
                blocked = @('DevHomeUpdate', 'OutlookUpdate', 'ChatAutoInstall')
                workCompleted = @('DevHomeUpdate', 'OutlookUpdate', 'ChatAutoInstall')
                failed = @()
            }
            featuresEnabled     = @($planFacts.removals.featuresEnabled)
            ai = [ordered]@{
                policy = [string]$planFacts.removals.aiPolicy
                catalogVersion = [int]$planFacts.removals.aiCatalogVersion
                appxPrefixes = @($planFacts.removals.aiAppxPrefixes)
                appxRemoved = @()
                optionalFeaturesRemoved = @()
                registryPoliciesApplied = @($planFacts.removals.aiRegistryPolicies)
                servicesDisabled = @()
                scheduledTasksDisabled = @()
                aggressiveActions = @($planFacts.removals.aiAggressiveActions)
                failed = @()
                recoveryBundlePath = ''
            }
        }
        sizeDelta           = [ordered]@{
            sourceIsoBytes = 0
            installWimBeforeServicingBytes = 0
            installWimAfterServicingBytes = 0
            installWimAfterExportBytes = 0
            outputIsoBytes = 0
            outputMinusSourceBytes = 0
            outputToSourceRatio = 0
        }
        servicing           = [ordered]@{
            componentCleanup = 'StartComponentCleanup'
            resetBase = $false
            serviceabilityPolicy = 'Preserve component-store uninstall/repair metadata; do not run ResetBase by default.'
            updates = [ordered]@{
                mode = [string]$Config.Updates.Mode
                targetFeatureVersion = [string]$Config.Updates.TargetFeatureVersion
                releaseCadence = [string]$Config.Updates.ReleaseCadence
                includeOptionalPreviews = [bool]$Config.Updates.IncludeOptionalPreviews
                payloadRoot = [string]$Config.Updates.PayloadRoot
                qualitySecurity = [bool]$Config.Updates.QualitySecurity
                dynamicUpdate = [bool]$Config.Updates.DynamicUpdate
                defender = [bool]$Config.Updates.Defender
                dotnet = [bool]$Config.Updates.DotNet
                provisionedApps = [bool]$Config.Updates.ProvisionedApps
                appliedPackages = @()
                provisionedAppx = @()
                skipped = @()
                failed = @()
            }
        }
        tweaks              = [ordered]@{
            registryGroupsApplied = @($Config.RegistryTweaks)
            registryGroups        = @(
                foreach ($group in @($script:RegistryTweaks)) {
                    $status = if (@($Config.RegistryTweaks) -contains [string]$group.id) { 'pending' } else { 'skipped-not-selected' }
                    New-WinMintRegistryTweakDetail -Group $group -Status $status
                }
            )
        }
        policies            = [ordered]@{
            homePrivacy = [ordered]@{
                enabled = (@($Config.RegistryTweaks) -contains 'home-privacy-policy')
                telemetry = 'RequiredOnly'
                allowTelemetry = 1
            }
            laptopDefaults = [ordered]@{
                enabled = ((@($Config.RegistryTweaks) -contains 'storage-sense-policy') -and (@($Config.RegistryTweaks) -contains 'modern-standby-policy'))
            }
            locationPosture = [ordered]@{
                enabled = [bool]$Config.Privacy.Location
                findMyDeviceAllowed = [bool]$Config.Privacy.Location
            }
            storageSense = [ordered]@{
                enabled = (@($Config.RegistryTweaks) -contains 'storage-sense-policy')
                downloadsCleanup = 'disabled'
            }
            modernStandby = [ordered]@{
                networkConnectivity = if (@($Config.RegistryTweaks) -contains 'modern-standby-policy') { 'disabled' } else { 'unchanged' }
            }
            wpbt = [ordered]@{
                disableWpbtExecution = (@($Config.RegistryTweaks) -contains 'wpbt-policy')
            }
            dualBootClock = [ordered]@{
                realTimeIsUniversal = (@($Config.RegistryTweaks) -contains 'dual-boot-clock-policy')
            }
        }
        drivers             = [ordered]@{
            source        = [string]$Config.Drivers.Source
            path          = [string]$Config.Drivers.Path
            injectedCount = 0
            infNames      = @()
        }
        payloads            = [System.Collections.Generic.List[object]]::new()
        firstLogon          = [ordered]@{
            editors      = @($planFacts.firstLogon.editors)
            wslDistros   = @($planFacts.firstLogon.wslDistros)
            desktopLayers = @($planFacts.firstLogon.shellLayers)
        }
        riskFlags           = @(if ($Config.RegistryTweaks -contains 'hardware-bypass') { 'hardware-bypass' })
    }
}

function Set-WinMintManifestSetupPlanFact {
    param(
        [AllowNull()]$SetupPlan
    )

    if ($null -eq $script:WinMintBuildManifest -or $null -eq $SetupPlan) { return }

    $script:WinMintBuildManifest['setupPlan'] = [ordered]@{
        schemaVersion = [int]$SetupPlan.schemaVersion
        accountMode = [string]$SetupPlan.accountMode
        editionMode = [string]$SetupPlan.editionMode
        diskMode = [string]$SetupPlan.diskMode
        phases = @($SetupPlan.phases | ForEach-Object {
                [ordered]@{
                    id = [string]$_.id
                    context = [string]$_.context
                    entrypoint = [string]$_.entrypoint
                    responsibilities = @($_.responsibilities)
                }
            })
        stagedArtifacts = @($SetupPlan.stagedArtifacts)
        firstLogonModules = @($SetupPlan.firstLogon.modules)
        notes = @($SetupPlan.notes)
    }
}

function Set-WinMintManifestSizeDeltaFact {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Value
    )

    if ($null -eq $script:WinMintBuildManifest) { return }
    if (-not $script:WinMintBuildManifest.Contains('sizeDelta')) { return }
    if ($null -eq $Value) { return }
    $script:WinMintBuildManifest.sizeDelta[$Name] = [long]$Value
}

function Set-WinMintManifestSizeDeltaFromPath {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    Set-WinMintManifestSizeDeltaFact -Name $Name -Value (Get-Item -LiteralPath $Path).Length
}

function Set-WinMintManifestOutputIsoSizeFact {
    param(
        [Parameter(Mandatory)][long]$SizeBytes
    )

    if ($null -eq $script:WinMintBuildManifest) { return }
    Set-WinMintManifestSizeDeltaFact -Name 'outputIsoBytes' -Value $SizeBytes
    $sourceBytes = $script:WinMintBuildManifest.sizeDelta.sourceIsoBytes
    if ([long]$sourceBytes -gt 0) {
        $script:WinMintBuildManifest.sizeDelta.outputMinusSourceBytes = [long]$SizeBytes - [long]$sourceBytes
        $script:WinMintBuildManifest.sizeDelta.outputToSourceRatio = [math]::Round(([double]$SizeBytes / [double]$sourceBytes), 4)
    }
}

function Set-WinMintManifestSourceEditionsFact {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$EditionNames
    )

    if ($null -eq $script:WinMintBuildManifest) { return }
    $script:WinMintBuildManifest.source.editions = @($EditionNames)
}

function Set-WinMintManifestServicedWimCacheFact {
    param([bool]$Restored)

    if ($null -eq $script:WinMintBuildManifest) { return }
    $script:WinMintBuildManifest | Add-Member -NotePropertyName servicedWimCacheRestored -NotePropertyValue $Restored -Force
}

function Set-WinMintManifestDriverFacts {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$InfNames
    )

    if ($null -eq $script:WinMintBuildManifest) { return }
    $script:WinMintBuildManifest.drivers.injectedCount = @($InfNames).Count
    $script:WinMintBuildManifest.drivers.infNames = @($InfNames | Sort-Object -Unique)
}

function Set-WinMintManifestLanguagePackageRemovalFacts {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$PackageNames
    )

    if ($null -eq $script:WinMintBuildManifest) { return }
    $script:WinMintBuildManifest.removals.languagePackagesRemoved = @($PackageNames)
    $script:WinMintBuildManifest.removals.languagePackagesRemovedCount = @($PackageNames).Count
}

function Set-WinMintManifestComponentCleanupFact {
    param(
        [string]$ComponentCleanup = 'StartComponentCleanup',
        [bool]$ResetBase = $false,
        [string]$ServiceabilityPolicy = 'Preserve component-store uninstall/repair metadata; do not run ResetBase by default.'
    )

    if ($null -eq $script:WinMintBuildManifest) { return }
    $script:WinMintBuildManifest.servicing.componentCleanup = $ComponentCleanup
    $script:WinMintBuildManifest.servicing.resetBase = $ResetBase
    $script:WinMintBuildManifest.servicing.serviceabilityPolicy = $ServiceabilityPolicy
}

function Add-WinMintManifestUpdatePackageFact {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Path
    )

    if ($null -eq $script:WinMintBuildManifest) { return }
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    $script:WinMintBuildManifest.servicing.updates.appliedPackages += [ordered]@{
        category = $Category
        path = $item.FullName
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        sizeBytes = [long]$item.Length
    }
}

function Add-WinMintManifestUpdateAppxFact {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$DependencyCount = 0
    )

    if ($null -eq $script:WinMintBuildManifest) { return }
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    $script:WinMintBuildManifest.servicing.updates.provisionedAppx += [ordered]@{
        path = $item.FullName
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        sizeBytes = [long]$item.Length
        dependencyCount = $DependencyCount
    }
}

function Add-WinMintManifestUpdateSkippedFact {
    param([Parameter(Mandatory)][string]$Message)

    if ($null -eq $script:WinMintBuildManifest) { return }
    $script:WinMintBuildManifest.servicing.updates.skipped += $Message
}

function Add-WinMintManifestUpdateFailureFact {
    param(
        [Parameter(Mandatory)][string]$Category,
        [string]$Path = '',
        [Parameter(Mandatory)][string]$ErrorMessage
    )

    if ($null -eq $script:WinMintBuildManifest) { return }
    $script:WinMintBuildManifest.servicing.updates.failed += [ordered]@{
        category = $Category
        path = $Path
        error = $ErrorMessage
    }
}

function Set-WinMintManifestCapabilityRemovalFacts {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$CapabilityNames
    )

    if ($null -eq $script:WinMintBuildManifest) { return }
    $script:WinMintBuildManifest.removals.capabilitiesRemoved = @($CapabilityNames)
}

function Set-WinMintManifestWindowsPackageRemovalFacts {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$PackageNames
    )

    if ($null -eq $script:WinMintBuildManifest) { return }
    $script:WinMintBuildManifest.removals.windowsPackagesRemoved = @($PackageNames)
}

function Add-WinMintManifestAiOptionalFeatureRemovalFacts {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$RemovedFeatures,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Failed
    )

    if ($null -eq $script:WinMintBuildManifest -or -not $script:WinMintBuildManifest.removals.ai) { return }
    $existing = @($script:WinMintBuildManifest.removals.ai.optionalFeaturesRemoved)
    $script:WinMintBuildManifest.removals.ai.optionalFeaturesRemoved = @($existing + @($RemovedFeatures) | Sort-Object -Unique)
    $script:WinMintBuildManifest.removals.ai.failed = @(@($script:WinMintBuildManifest.removals.ai.failed) + @($Failed))
}

function Set-WinMintManifestOneDriveSetupStubRemovalFacts {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Removed,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$NotFound,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Failed
    )

    if ($null -eq $script:WinMintBuildManifest) { return }
    $script:WinMintBuildManifest.removals['oneDriveSetupStubs'] = [ordered]@{
        intent = 'Do not offer or auto-provision OneDrive on fresh installs; users can reinstall OneDrive later from Microsoft or winget.'
        removed = @($Removed)
        notFound = @($NotFound)
        failed = @($Failed)
    }
}

function Set-WinMintManifestAppxRemovalFacts {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$RemovedPackageNames,
        [int]$RemovedCount = @($RemovedPackageNames).Count,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$AiRemovedPackageNames
    )

    if ($null -eq $script:WinMintBuildManifest) { return }
    $script:WinMintBuildManifest.removals.appxRemoved = @($RemovedPackageNames)
    $script:WinMintBuildManifest.removals.appxRemovedCount = [int]$RemovedCount
    if ($script:WinMintBuildManifest.removals.ai -and @($AiRemovedPackageNames).Count -gt 0) {
        $script:WinMintBuildManifest.removals.ai.appxRemoved = @(
            @($script:WinMintBuildManifest.removals.ai.appxRemoved) + @($AiRemovedPackageNames) |
                Sort-Object -Unique
        )
    }
}

function Set-WinMintManifestUsbMediaFact {
    param([Parameter(Mandatory)]$Result)

    if ($null -eq $script:WinMintBuildManifest) { return }
    $script:WinMintBuildManifest['usbMedia'] = [ordered]@{
        enabled = $true
        status = [string]$Result.Status
        writtenAt = [string]$Result.WrittenAt
        diskNumber = [int]$Result.DiskNumber
        diskModel = [string]$Result.DiskModel
        diskSizeBytes = [long]$Result.DiskSizeBytes
        partitionScheme = 'GPT'
        bootMode = 'UEFI'
        installFilesystem = 'NTFS'
        installDrive = [string]$Result.InstallDrive
        helper = 'UEFI:NTFS'
        helperVersion = [string]$Result.HelperVersion
        helperSourceUrl = [string]$Result.HelperSourceUrl
        helperSha256 = [string]$Result.HelperSha256
        architecture = [string]$Result.Architecture
    }
}

function Set-WinMintManifestUsbMediaFailureFact {
    param(
        [Parameter(Mandatory)][int]$DiskNumber,
        [Parameter(Mandatory)][string]$ErrorMessage
    )

    if ($null -eq $script:WinMintBuildManifest) { return }
    $script:WinMintBuildManifest['usbMedia'] = [ordered]@{
        enabled = $true
        status = 'failed'
        diskNumber = [int]$DiskNumber
        error = $ErrorMessage
    }
}

function Add-WinMintManifestRegistryTweakEvent {
    param(
        [Parameter(Mandatory)]$Group,
        [Parameter(Mandatory)][ValidateSet('applied', 'skipped-not-selected', 'skipped-conditional', 'failed')] [string]$Status,
        [string]$ErrorMessage = ''
    )

    if ($null -eq $script:WinMintBuildManifest) { return }
    if (-not $script:WinMintBuildManifest.tweaks.Contains('registryGroups')) {
        $script:WinMintBuildManifest.tweaks['registryGroups'] = @()
    }

    $detail = New-WinMintRegistryTweakDetail -Group $Group -Status $Status -ErrorMessage $ErrorMessage
    $groups = [System.Collections.Generic.List[object]]::new()
    $replaced = $false
    foreach ($existing in @($script:WinMintBuildManifest.tweaks.registryGroups)) {
        if ([string]$existing.id -eq [string]$detail.id) {
            $groups.Add($detail) | Out-Null
            $replaced = $true
        }
        else {
            $groups.Add($existing) | Out-Null
        }
    }
    if (-not $replaced) { $groups.Add($detail) | Out-Null }
    $script:WinMintBuildManifest.tweaks.registryGroups = $groups.ToArray()
}

function New-WinMintTweakRollbackRegContent {
    param([object[]]$Groups)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('Windows Registry Editor Version 5.00') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('; WinMint best-effort tweak rollback. Review before importing.') | Out-Null
    foreach ($group in @($Groups)) {
        $setOps = @(Get-WinMintRegistryTweakGroupValue -Group $group -Name 'set' -Default @())
        $removeOps = @(Get-WinMintRegistryTweakGroupValue -Group $group -Name 'remove' -Default @())
        $wroteHeader = $false
        foreach ($entry in $setOps) {
            $undo = Get-WinMintRegistryTweakGroupValue -Group $entry -Name 'undo'
            if ($null -eq $undo) { continue }
            if (-not $wroteHeader) {
                $lines.Add('') | Out-Null
                $lines.Add("; $([string](Get-WinMintRegistryTweakGroupValue -Group $group -Name 'id'))") | Out-Null
                $wroteHeader = $true
            }
            $path = ConvertTo-WinMintRegistryAuditPath -Path ([string](Get-WinMintRegistryTweakGroupValue -Group $entry -Name 'path'))
            $name = [string](Get-WinMintRegistryTweakGroupValue -Group $entry -Name 'name')
            $action = [string](Get-WinMintRegistryTweakGroupValue -Group $undo -Name 'action' -Default 'set')
            $lines.Add("[$path]") | Out-Null
            if ($action -eq 'delete') {
                $regName = if ([string]::IsNullOrWhiteSpace($name)) { '@' } else { ConvertTo-WinMintRegStringText -Value $name }
                $lines.Add("$regName=-") | Out-Null
            }
            else {
                $type = [string](Get-WinMintRegistryTweakGroupValue -Group $undo -Name 'type' -Default ([string](Get-WinMintRegistryTweakGroupValue -Group $entry -Name 'type')))
                $value = [string](Get-WinMintRegistryTweakGroupValue -Group $undo -Name 'value' -Default '')
                $lines.Add((ConvertTo-WinMintRegValueLine -Name $name -Type $type -Value $value)) | Out-Null
            }
            $lines.Add('') | Out-Null
        }
        foreach ($entry in $removeOps) {
            $restore = Get-WinMintRegistryTweakGroupValue -Group $entry -Name 'restore'
            if ($null -eq $restore) { continue }
            if (-not $wroteHeader) {
                $lines.Add('') | Out-Null
                $lines.Add("; $([string](Get-WinMintRegistryTweakGroupValue -Group $group -Name 'id'))") | Out-Null
                $wroteHeader = $true
            }
            $path = ConvertTo-WinMintRegistryAuditPath -Path ([string](Get-WinMintRegistryTweakGroupValue -Group $entry -Name 'path'))
            $lines.Add("[$path]") | Out-Null
            foreach ($value in @(Get-WinMintRegistryTweakGroupValue -Group $restore -Name 'values' -Default @())) {
                $lines.Add((ConvertTo-WinMintRegValueLine `
                    -Name ([string](Get-WinMintRegistryTweakGroupValue -Group $value -Name 'name')) `
                    -Type ([string](Get-WinMintRegistryTweakGroupValue -Group $value -Name 'type')) `
                    -Value ([string](Get-WinMintRegistryTweakGroupValue -Group $value -Name 'value')))) | Out-Null
            }
            $lines.Add('') | Out-Null
        }
    }

    return ($lines.ToArray() -join "`r`n") + "`r`n"
}

function Save-WinMintTweakAuditArtifacts {
    param([Parameter(Mandatory)][string]$OutputDir)

    if ($null -eq $script:WinMintBuildManifest) { return $null }
    $groups = @($script:WinMintBuildManifest.tweaks.registryGroups)
    $audit = [ordered]@{
        generatedAt = [DateTimeOffset]::Now.ToString('o')
        selected = @($script:WinMintBuildManifest.tweaks.registryGroupsApplied)
        groups = $groups
        summary = [ordered]@{
            applied = @($groups | Where-Object status -eq 'applied').Count
            skippedNotSelected = @($groups | Where-Object status -eq 'skipped-not-selected').Count
            skippedConditional = @($groups | Where-Object status -eq 'skipped-conditional').Count
            failed = @($groups | Where-Object status -eq 'failed').Count
        }
    }

    $jsonPath = Join-Path $OutputDir 'WinMint-TweakAudit.json'
    $mdPath = Join-Path $OutputDir 'WinMint-TweakAudit.md'
    $regPath = Join-Path $OutputDir 'WinMint-TweakRollback.reg'
    $audit | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    Set-Content -LiteralPath $regPath -Value (New-WinMintTweakRollbackRegContent -Groups $script:RegistryTweaks) -Encoding Unicode

    $rows = @(
        '# WinMint Tweak Audit'
        ''
        "| Status | Count |"
        "| --- | ---: |"
        "| Applied | $($audit.summary.applied) |"
        "| Skipped (not selected) | $($audit.summary.skippedNotSelected) |"
        "| Skipped (conditional) | $($audit.summary.skippedConditional) |"
        "| Failed | $($audit.summary.failed) |"
        ''
        '## Registry Groups'
        ''
        '| ID | Status | Risk | Rollback | Intent |'
        '| --- | --- | --- | --- | --- |'
    )
    foreach ($group in $groups) {
        $rows += "| $($group.id) | $($group.status) | $($group.risk) | $($group.rollbackCoverage) | $($group.intent) |"
    }
    Set-Content -LiteralPath $mdPath -Value ($rows -join "`n") -Encoding UTF8

    return [pscustomobject]@{ Json = $jsonPath; Markdown = $mdPath; Rollback = $regPath }
}

function Save-WinMintRecoveryBundle {
    param([Parameter(Mandatory)][string]$OutputDir)

    if ($null -eq $script:WinMintBuildManifest) { return $null }
    $recoveryDir = Join-Path $OutputDir 'recovery'
    $null = New-Item -ItemType Directory -Path $recoveryDir -Force

    $aiScriptPath = Join-Path $recoveryDir 'Recover-WinMintAiPolicy.ps1'
    $dmaScriptPath = Join-Path $recoveryDir 'Recover-WinMintDmaRegion.ps1'
    $policyScriptPath = Join-Path $recoveryDir 'Recover-WinMintSystemPolicies.ps1'
    $jsonPath = Join-Path $recoveryDir 'WinMint-Recovery.json'
    $readmePath = Join-Path $recoveryDir 'README.md'

    $aiScript = @'
#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Continue'
$policyRoots = @(
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI',
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot',
  'HKLM:\SOFTWARE\Policies\Microsoft\Edge',
  'HKLM:\SOFTWARE\Policies\WindowsNotepad',
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy',
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\generativeAI',
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\systemAIModels',
  'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI'
)
foreach ($path in $policyRoots) {
  if (Test-Path -LiteralPath $path) {
    if ($PSCmdlet.ShouldProcess($path, 'remove WinMint AI policy key')) {
      Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}
foreach ($svcName in @('WSAIFabricSvc')) {
  $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
  if ($svc -and $PSCmdlet.ShouldProcess($svcName, 'set service startup to manual')) {
    Set-Service -Name $svcName -StartupType Manual -ErrorAction SilentlyContinue
  }
}
Get-ScheduledTask -ErrorAction SilentlyContinue |
  Where-Object { $_.TaskName -match '(?i)Recall|WindowsAI|Copilot' -or $_.TaskPath -match '(?i)Recall|WindowsAI|Copilot' } |
  ForEach-Object {
    if ($PSCmdlet.ShouldProcess("$($_.TaskPath)$($_.TaskName)", 'enable scheduled task')) {
      Enable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue | Out-Null
    }
  }
Write-Host 'WinMint AI policy rollback finished. Removed provisioned AppX/optional feature payloads are not restored by this script.'
'@
    Set-Content -LiteralPath $aiScriptPath -Value $aiScript -Encoding UTF8

    $dma = $script:WinMintBuildManifest.regional.dmaInterop
    $locationServicesEnabledLiteral = if ([string]$dma.locationServicesPolicy -eq 'enabled') { '$true' } else { '$false' }
    $dmaScript = @"
#Requires -Version 5.1
[CmdletBinding()]
param(
  [string]`$TimeZoneId = '$([string]$dma.restoredTimeZoneId)',
  [string]`$UserLocale = '$([string]$dma.restoredUserLocale)',
  [int]`$HomeLocationGeoId = $([int]$dma.restoredHomeLocationGeoId),
  [bool]`$LocationServicesEnabled = $locationServicesEnabledLiteral
)

`$ErrorActionPreference = 'Continue'
if (-not [string]::IsNullOrWhiteSpace(`$TimeZoneId)) { Set-TimeZone -Id `$TimeZoneId -ErrorAction SilentlyContinue }
if (`$HomeLocationGeoId -gt 0) { Set-WinHomeLocation -GeoId `$HomeLocationGeoId -ErrorAction SilentlyContinue }
if (-not [string]::IsNullOrWhiteSpace(`$UserLocale)) { Set-Culture -CultureInfo `$UserLocale -ErrorAction SilentlyContinue }
if (Get-Command Copy-UserInternationalSettingsToSystem -ErrorAction SilentlyContinue) {
  Copy-UserInternationalSettingsToSystem -WelcomeScreen `$true -NewUser `$true -ErrorAction SilentlyContinue
}
if (`$LocationServicesEnabled) {
  reg.exe add HKLM\SYSTEM\CurrentControlSet\Services\tzautoupdate /v Start /t REG_DWORD /d 3 /f | Out-Null
  Set-Service -Name tzautoupdate -StartupType Manual -ErrorAction SilentlyContinue
} else {
  reg.exe add HKLM\SYSTEM\CurrentControlSet\Services\tzautoupdate /v Start /t REG_DWORD /d 4 /f | Out-Null
  Stop-Service -Name tzautoupdate -ErrorAction SilentlyContinue
  Set-Service -Name tzautoupdate -StartupType Disabled -ErrorAction SilentlyContinue
}
Write-Host 'WinMint DMA-visible region restore finished.'
"@
    Set-Content -LiteralPath $dmaScriptPath -Value $dmaScript -Encoding UTF8

    $policyScript = @'
#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Continue'
function Remove-RegValueIfPresent {
  param([string]$Path, [string]$Name)
  if (-not (Test-Path -LiteralPath $Path)) { return }
  if ($PSCmdlet.ShouldProcess("$Path\$Name", 'remove registry value')) {
    Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
  }
}
function Remove-RegKeyIfPresent {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return }
  if ($PSCmdlet.ShouldProcess($Path, 'remove registry key')) {
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
  }
}

foreach ($name in 'DevHomeUpdate', 'OutlookUpdate', 'ChatAutoInstall') {
  Remove-RegValueIfPresent -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\$name" -Name 'workCompleted'
}
foreach ($name in 'DisableLocation', 'DisableWindowsLocationProvider', 'DisableLocationScripting') {
  Remove-RegValueIfPresent -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Name $name
}
Remove-RegValueIfPresent -Path 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice' -Name 'AllowFindMyDevice'
foreach ($root in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy', 'HKU:\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy') {
  foreach ($name in '01', '04', '08', '32') { Remove-RegValueIfPresent -Path $root -Name $name }
}
Remove-RegKeyIfPresent -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9'
Remove-RegValueIfPresent -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'DisableWpbtExecution'
Remove-RegValueIfPresent -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -Name 'RealTimeIsUniversal'
foreach ($name in 'AllowAutoGameMode', 'AutoGameModeEnabled') { Remove-RegValueIfPresent -Path 'HKCU:\Software\Microsoft\GameBar' -Name $name }
Remove-RegValueIfPresent -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode'
Remove-RegValueIfPresent -Path 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -Name 'DirectXUserGlobalSettings'
foreach ($name in 'LastActiveClick', 'SnapAssist', 'EnableSnapBar', 'EnableSnapAssistFlyout') {
  Remove-RegValueIfPresent -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name $name
}
Write-Host 'WinMint system policy rollback finished. Removed provisioned AppX/optional feature payloads are not restored by this script.'
'@
    Set-Content -LiteralPath $policyScriptPath -Value $policyScript -Encoding UTF8

    $recovery = [ordered]@{
        generatedAt = [DateTimeOffset]::Now.ToString('o')
        aiPolicy = $script:WinMintBuildManifest.removals.ai.policy
        aiRecoveryScript = $aiScriptPath
        dmaRecoveryScript = $dmaScriptPath
        systemPolicyRecoveryScript = $policyScriptPath
        cannotAutomaticallyRestore = @(
            'Removed provisioned AppX payloads',
            'Removed optional feature payloads',
            'Any CBS packages removed by internal experimental mode'
        )
    }
    $recovery | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $readme = @(
        '# WinMint Recovery Bundle'
        ''
        'These scripts reverse only serviceable policy, service, task, visible-region, and selected user-preference registry state.'
        ''
        'They do not reinstall AppX packages, optional feature payloads, or CBS packages removed from the image.'
        'To restore those payloads, rebuild from the original source ISO, reinstall from Microsoft Store/winget where available, or perform a Windows repair install.'
        ''
        'This folder is a build output sidecar. It is not staged into the installed Windows system and does not create maintenance tasks.'
    ) -join "`n"
    Set-Content -LiteralPath $readmePath -Value $readme -Encoding UTF8

    if ($script:WinMintBuildManifest.removals.ai) {
        $script:WinMintBuildManifest.removals.ai.recoveryBundlePath = $recoveryDir
    }
    return [pscustomobject]@{ Directory = $recoveryDir; Ai = $aiScriptPath; Dma = $dmaScriptPath; SystemPolicies = $policyScriptPath; Json = $jsonPath; Readme = $readmePath }
}

function Add-WinMintManifestPayload {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$SourceUrl,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Sha256,
        [Parameter(Mandatory)][long]$SizeBytes
    )
    if ($null -eq $script:WinMintBuildManifest) { return }
    $key = '{0}|{1}|{2}|{3}|{4}' -f $Name, $SourceUrl, $Version, $Sha256, $SizeBytes
    foreach ($payload in @($script:WinMintBuildManifest.payloads)) {
        $existingKey = '{0}|{1}|{2}|{3}|{4}' -f `
            ([string]$payload.name),
            ([string]$payload.sourceUrl),
            ([string]$payload.version),
            ([string]$payload.sha256),
            ([long]$payload.sizeBytes)
        if ($existingKey -eq $key) { return }
    }

    $script:WinMintBuildManifest.payloads.Add([ordered]@{
        name      = $Name
        sourceUrl = $SourceUrl
        version   = $Version
        sha256    = $Sha256
        sizeBytes = $SizeBytes
    })
}

function Get-WinMintDeduplicatedManifestPayload {
    param([object[]]$Payloads)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $deduped = [System.Collections.Generic.List[object]]::new()
    foreach ($payload in @($Payloads)) {
        if ($null -eq $payload) { continue }
        $key = '{0}|{1}|{2}|{3}|{4}' -f `
            ([string]$payload.name),
            ([string]$payload.sourceUrl),
            ([string]$payload.version),
            ([string]$payload.sha256),
            ([long]$payload.sizeBytes)
        if ($seen.Add($key)) {
            $deduped.Add($payload) | Out-Null
        }
    }

    return $deduped.ToArray()
}

function Save-WinMintBuildManifest {
    param(
        [Parameter(Mandatory)][string]$OutputDir,
        [string]$OutputIsoPath = '',
        [switch]$DryRun,
        [switch]$Failed
    )
    if ($null -eq $script:WinMintBuildManifest) { return }

    $started = [DateTimeOffset]::Parse($script:WinMintBuildManifest.builtAt)
    $script:WinMintBuildManifest.buildDurationSeconds = [math]::Round(([DateTimeOffset]::Now - $started).TotalSeconds, 1)
    $script:WinMintBuildManifest.buildResult = if ($Failed) { 'failed' } elseif ($DryRun) { 'dry-run' } else { 'success' }

    if (-not [string]::IsNullOrWhiteSpace($OutputIsoPath) -and (Test-Path -LiteralPath $OutputIsoPath)) {
        $isoHash = (Get-FileHash -LiteralPath $OutputIsoPath -Algorithm SHA256).Hash
        $isoSize = (Get-Item -LiteralPath $OutputIsoPath).Length
        $script:WinMintBuildManifest['output'] = [ordered]@{
            isoPath   = $OutputIsoPath
            sha256    = $isoHash
            sizeBytes = $isoSize
        }
    }

    $script:WinMintBuildManifest.payloads = @(Get-WinMintDeduplicatedManifestPayload -Payloads @($script:WinMintBuildManifest.payloads))
    $null = Save-WinMintTweakAuditArtifacts -OutputDir $OutputDir
    $null = Save-WinMintRecoveryBundle -OutputDir $OutputDir

    $path = Join-Path $OutputDir 'WinMint-BuildManifest.json'
    $script:WinMintBuildManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}
