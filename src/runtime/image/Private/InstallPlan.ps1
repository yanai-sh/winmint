#Requires -Version 7.3

function New-WinMintInstallPlanFromBuildConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$BuildConfig
    )

    $setupProfile = New-WinMintSetupProfile -BuildConfig $BuildConfig
    $agentProfile = New-WinMintAgentProfile -BuildConfig $BuildConfig
    $setupPlan = New-WinMintSetupPlan `
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
                setupUserLocale = [string]$BuildConfig.SetupUserLocale
                setupHomeLocationGeoId = [int]$BuildConfig.SetupHomeLocationGeoId
                restoreUserLocale = [string]$BuildConfig.UserLocale
                restoreHomeLocationGeoId = [int]$BuildConfig.HomeLocationGeoId
                restoreLocationServices = [bool]$BuildConfig.DmaInterop.RestoreLocationServices
            }
            removals = [ordered]@{
                appxPrefixes = @($BuildConfig.AppxPackages)
                aiPolicy = [string]$BuildConfig.AiRemoval.Policy
                aiAppxPrefixes = @($BuildConfig.AiRemoval.AppxPrefixes)
                aiOptionalFeatures = @($BuildConfig.AiRemoval.OptionalFeatures)
                removeEdge = [bool]$setupProfile.edge.removeEdge
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
                wslDistros = @($BuildConfig.Wsl2Distros)
                launcher = [string]$BuildConfig.Launcher
                shellLayers = @(
                    if ([bool]$BuildConfig.InstallWindhawk) { 'windhawk' }
                    if ([bool]$BuildConfig.InstallYasb) { 'yasb' }
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
