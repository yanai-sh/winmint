#Requires -Version 7.3

function Test-BuildProfileSchema {
    $schema = Get-WinMintPath -Name BuildProfileSchema
    if (-not (Test-Path -LiteralPath $schema)) {
        Add-ValidationError 'Build profile schema is missing.'
        return
    }
    $sample = [pscustomobject][ordered]@{
        schemaVersion = 2
        createdAt = [DateTimeOffset]::Now.ToString('o')
        profileName = 'Developer'
        source = [pscustomobject][ordered]@{
            isoPath = 'C:\ISO\Win11.iso'
            architecture = 'amd64'
        }
        target = [pscustomobject][ordered]@{
            device = 'ThisPC'
            editionMode = 'TargetLicense'
            edition = ''
            diskMode = 'Manual'
            diskLayout = [pscustomobject][ordered]@{
                mode = 'Manual'
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
        identity = [pscustomobject][ordered]@{
            computerName = 'WinMint'
            accountName = 'dev'
            autoLogon = $false
            passwordSet = $false
            passwordIncluded = $false
        }
        regional = [pscustomobject][ordered]@{
            timeZoneId = 'UTC'
            uiLanguage = 'en-US'
            systemLocale = 'en-US'
            uiLanguageFallback = 'en-US'
            userLocale = 'en-US'
            inputLocale = '0409:00000409'
            homeLocationGeoId = 244
        }
        drivers = [pscustomobject][ordered]@{
            source = 'None'
            path = ''
            exportHostDrivers = $false
        }
        desktop = [pscustomobject][ordered]@{
            cursorPack = 'Windows11Modern'
            layers = @('standard')
        }
        development = [pscustomobject][ordered]@{
            editors = @('cursor')
            wsl = [pscustomobject][ordered]@{
                enabled = $true
                distros = @('Ubuntu')
            }
        }
        removals = [pscustomobject][ordered]@{
            advertising = $true
            gaming = $true
            communication = $true
            microsoftApps = $true
            aiPolicy = 'Core'
            effectiveAppx = @('Microsoft.BingNews')
        }
        privacy = [pscustomobject][ordered]@{
            telemetry = $true
            advertisingId = $true
            location = $true
            timeline = $true
        }
        tweaks = [pscustomobject][ordered]@{
            darkMode = $true
            fileExtensions = $true
            stickyKeys = $true
            hardwareBypass = $false
            dmaInterop = $true
        }
    }
    Test-JsonObjectAgainstSchema -Value $sample -SchemaPath $schema -Label 'winmint.buildprofile sample'

    $badDriver = $sample | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $badDriver.drivers.source = 'Host'
    $badDriver.drivers.exportHostDrivers = $false
    Test-JsonObjectRejectedBySchema -Value $badDriver -SchemaPath $schema -Label 'winmint.buildprofile driver invariant'

    $badCursor = $sample | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $badCursor.desktop.cursorPack = 'OtherPack'
    Test-JsonObjectRejectedBySchema -Value $badCursor -SchemaPath $schema -Label 'winmint.buildprofile cursor invariant'

    $badPassword = $sample | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $badPassword.identity.passwordIncluded = $true
    Test-JsonObjectRejectedBySchema -Value $badPassword -SchemaPath $schema -Label 'winmint.buildprofile password invariant'

    $badDualBoot = $sample | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $badDualBoot.target.diskMode = 'DualBootReserved'
    $badDualBoot.target.diskLayout.mode = 'DualBootReserved'
    $badDualBoot.target.diskLayout.preset = ''
    Test-JsonObjectRejectedBySchema -Value $badDualBoot -SchemaPath $schema -Label 'winmint.buildprofile dual boot preset required'
}

function Test-BuildManifestSchema {
    $schemaPath = Get-WinMintPath -Name BuildManifestSchema
    if (-not (Test-Path -LiteralPath $schemaPath)) {
        Add-ValidationError "winmint.buildmanifest.schema.json not found at $schemaPath"
        return
    }

    $valid = [ordered]@{
        schemaVersion        = 2
        builtAt              = '2026-01-01T00:00:00+00:00'
        buildDurationSeconds = 42.5
        buildResult          = 'success'
        source               = [ordered]@{
            isoPath      = 'C:\test.iso'
            architecture = 'amd64'
            editions     = @('Windows 11 Home Single Language')
        }
        target               = [ordered]@{
            diskMode = 'Manual'
            diskLayout = [ordered]@{
                mode = 'Manual'
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
            primaryAssumption = 'Windows11HomeSingleLanguageEnUS'
        }
        regional             = [ordered]@{
            timeZoneId = 'UTC'
            uiLanguage = 'en-US'
            systemLocale = 'en-US'
            userLocale = 'en-US'
            inputLocale = '0409:00000409'
            homeLocationGeoId = 244
            dmaInterop = [ordered]@{
                enabled = $true
                defaultEnabled = $true
                setupCountry = 'Ireland'
                setupUserLocale = 'en-IE'
                setupHomeLocationGeoId = 68
                setupLatchedCountry = 'Ireland'
                setupLatchedGeoId = 68
                restoreUserLocale = 'en-US'
                restoreHomeLocationGeoId = 244
                restoredUserLocale = 'en-US'
                restoredHomeLocationGeoId = 244
                restoredTimeZoneId = 'UTC'
                locationServicesPolicy = 'disabled'
            }
        }
        output               = [ordered]@{
            isoPath   = 'C:\output\WinMint.iso'
            sha256    = 'abc123def456'
            sizeBytes = 4123456789
        }
        removals             = [ordered]@{
            appxPrefixes        = @('Microsoft.BingNews')
            appxCatalogVersion  = 1
            appxRemoved         = @('Microsoft.BingNews_1.0.0.0_neutral__8wekyb3d8bbwe')
            appxRemovedCount    = 1
            capabilitiesRemoved = @()
            windowsPackagesRemoved = @()
            languagePackagesRemoved = @()
            languagePackagesRemovedCount = 0
            oobeRehydration = [ordered]@{
                blocked = @('DevHomeUpdate', 'OutlookUpdate', 'ChatAutoInstall')
                workCompleted = @('DevHomeUpdate', 'OutlookUpdate', 'ChatAutoInstall')
                failed = @()
            }
            featuresEnabled     = @('Microsoft-Windows-Subsystem-Linux')
            ai = [ordered]@{
                policy = 'Core'
                catalogVersion = 1
                appxPrefixes = @()
                appxRemoved = @()
                optionalFeaturesRemoved = @()
                registryPoliciesApplied = @('windows-ai-core-policy')
                servicesDisabled = @()
                scheduledTasksDisabled = @()
                aggressiveActions = @()
                failed = @()
                recoveryBundlePath = ''
            }
        }
        sizeDelta            = [ordered]@{
            sourceIsoBytes = 5123456789
            installWimBeforeServicingBytes = 4321000000
            installWimAfterServicingBytes = 4210000000
            installWimAfterExportBytes = 3900000000
            outputIsoBytes = 4123456789
            outputMinusSourceBytes = -1000000000
            outputToSourceRatio = 0.8048
        }
        servicing            = [ordered]@{
            componentCleanup = 'StartComponentCleanup'
            resetBase = $false
            serviceabilityPolicy = 'Preserve component-store uninstall/repair metadata; do not run ResetBase by default.'
        }
        tweaks               = [ordered]@{
            registryGroupsApplied = @('developer-qol')
            registryGroups        = @(
                [ordered]@{
                    id                 = 'developer-qol'
                    description        = 'Explorer QoL (file extensions and hidden files)'
                    scope              = 'default user registry'
                    risk               = 'low'
                    reversible         = $true
                    phase              = 'offline-image'
                    intent             = 'Make Explorer friendlier for development by exposing file extensions and hidden files.'
                    status             = 'applied'
                    setOperations      = 2
                    removeOperations   = 0
                    rollbackOperations = 2
                    rollbackCoverage   = 'full'
                    error              = ''
                }
            )
        }
        policies             = [ordered]@{
            homePrivacy = [ordered]@{ enabled = $true; telemetry = 'RequiredOnly'; allowTelemetry = 1 }
            laptopDefaults = [ordered]@{ enabled = $true }
            locationPosture = [ordered]@{ enabled = $true; findMyDeviceAllowed = $true }
            storageSense = [ordered]@{ enabled = $true; downloadsCleanup = 'disabled' }
            modernStandby = [ordered]@{ networkConnectivity = 'disabled' }
            wpbt = [ordered]@{ disableWpbtExecution = $true }
            dualBootClock = [ordered]@{ realTimeIsUniversal = $false }
        }
        drivers              = [ordered]@{
            source        = 'None'
            path          = ''
            injectedCount = 0
            infNames      = @()
        }
        payloads             = @(
            [ordered]@{
                name      = 'PowerShell 7'
                sourceUrl = 'https://github.com/PowerShell/PowerShell/releases/download/v7.5.0/PowerShell-7.5.0-win-x64.zip'
                version   = 'v7.5.0'
                sha256    = 'deadbeef'
                sizeBytes = 104857600
            }
        )
        firstLogon           = [ordered]@{
            editors       = @('vscode')
            wslDistros    = @('ubuntu')
            desktopLayers = @('windhawk')
        }
        riskFlags            = @()
    }
    $validPso = $valid | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    Test-JsonObjectAgainstSchema -Value $validPso -SchemaPath $schemaPath -Label 'winmint.buildmanifest (valid)'

    $noResult = $valid | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $noResult.PSObject.Properties.Remove('buildResult')
    Test-JsonObjectRejectedBySchema -Value $noResult -SchemaPath $schemaPath -Label 'winmint.buildmanifest missing buildResult'

    $badResult = $valid | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $badResult.buildResult = 'unknown'
    Test-JsonObjectRejectedBySchema -Value $badResult -SchemaPath $schemaPath -Label 'winmint.buildmanifest invalid buildResult enum'

    $failedNoOutput = $valid | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $failedNoOutput.buildResult = 'failed'
    $failedNoOutput.PSObject.Properties.Remove('output')
    Test-JsonObjectAgainstSchema -Value $failedNoOutput -SchemaPath $schemaPath -Label 'winmint.buildmanifest (failed; no output)'
}

function Test-AgentStateSchema {
    $schemaPath = Get-WinMintPath -Name AgentStateSchema
    if (-not (Test-Path -LiteralPath $schemaPath)) {
        Add-ValidationError "winmint.agentstate.schema.json not found at $schemaPath"
        return
    }

    $valid = [pscustomobject][ordered]@{
        version = 1
        run = [pscustomobject][ordered]@{
            startedAt = '2026-01-01T00:00:00+00:00'
            status = 'running'
            failedSteps = @()
            hostArchitecture = 'arm64'
            interactiveFirstLogon = $true
        }
        steps = [pscustomobject][ordered]@{
            profiles = [pscustomobject][ordered]@{
                status = 'ok'
                attempts = 1
                updatedAt = '2026-01-01T00:00:02+00:00'
            }
            wsl = [pscustomobject][ordered]@{
                status = 'needsReboot'
                attempts = 1
                result = [pscustomobject][ordered]@{ missingDistros = @('Ubuntu') }
            }
        }
    }
    Test-JsonObjectAgainstSchema -Value $valid -SchemaPath $schemaPath -Label 'winmint.agentstate (valid)'

    $missingStatus = $valid | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $missingStatus.steps.profiles.PSObject.Properties.Remove('status')
    Test-JsonObjectRejectedBySchema -Value $missingStatus -SchemaPath $schemaPath -Label 'winmint.agentstate step status required'

    $badStatus = $valid | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $badStatus.steps.wsl.status = 'reboot'
    Test-JsonObjectRejectedBySchema -Value $badStatus -SchemaPath $schemaPath -Label 'winmint.agentstate invalid step status'
}
