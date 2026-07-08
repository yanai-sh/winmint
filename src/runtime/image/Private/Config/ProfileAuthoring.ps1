#Requires -Version 7.6

function Assert-WinMintWizardSettings {
    param(
        [Parameter(Mandatory)][object]$Settings
    )

    $required = @(
        'Profile', 'KeepEdge', 'KeepGaming', 'KeepCopilot', 'ISOPath', 'Architecture',
        'ComputerName', 'AccountName', 'AccountMode', 'TargetDevice', 'FormFactor', 'Edition',
        'DriverSource', 'DriverPath', 'InstallWindhawk', 'InstallYasb', 'InstallKomorebi',
        'InstallNilesoft', 'Editors', 'Browsers', 'Wsl2Distros', 'PrivLocation',
        'TweakHardwareBypass', 'TweakDmaInterop'
    )
    foreach ($name in $required) {
        if (-not $Settings.PSObject.Properties[$name]) {
            throw "Wizard settings missing required field: $name"
        }
    }

    if ([string]$Settings.Profile -ne 'WinMint') {
        throw 'Wizard settings Profile must be WinMint.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Settings.Architecture)) {
        throw 'Wizard settings must include Architecture.'
    }
    if ([string]$Settings.Architecture -eq 'Unknown') {
        throw 'Wizard settings must include a resolved Architecture before profile generation.'
    }

    $options = Get-WinMintOptionCatalog
    $enum = {
        param([string]$Value, [string]$Label, [string[]]$Allowed)
        if ($Allowed -notcontains $Value) {
            throw "Wizard settings $Label must be one of: $($Allowed -join ', ')."
        }
    }
    & $enum ([string]$Settings.Architecture) 'Architecture' @($options['UiArchitecture'])
    & $enum ([string]$Settings.AccountMode) 'AccountMode' @($options['AccountMode'])
    & $enum ([string]$Settings.TargetDevice) 'TargetDevice' @($options['TargetDevice'])
    & $enum ([string]$Settings.FormFactor) 'FormFactor' @($options['FormFactor'])
    & $enum ([string]$Settings.Edition) 'Edition' @($options['Edition'])
    & $enum ([string]$Settings.DriverSource) 'DriverSource' @($options['DriverSource'])

    foreach ($editor in @($Settings.Editors)) {
        if ($options['Editor'] -notcontains [string]$editor) {
            throw "Wizard settings Editors contains unknown id: $editor"
        }
    }
    foreach ($browser in @($Settings.Browsers)) {
        if ($options['Browser'] -notcontains [string]$browser) {
            throw "Wizard settings Browsers contains unknown id: $browser"
        }
    }
    foreach ($distro in @($Settings.Wsl2Distros)) {
        if ($options['WslDistro'] -notcontains [string]$distro) {
            throw "Wizard settings Wsl2Distros contains unknown id: $distro"
        }
    }

    $allowedKeys = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]$required,
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($property in $Settings.PSObject.Properties) {
        if (-not $allowedKeys.Contains($property.Name)) {
            throw "Wizard settings contain unknown key: $($property.Name)"
        }
    }
}

function Resolve-WinMintWizardProfileSettings {
    param(
        [Parameter(Mandatory)][object]$Settings
    )

    $editionSelection = Resolve-WinMintEditionSelection -Edition ([string]$Settings.Edition) -EditionSpecified $true
    $Settings | Add-Member -NotePropertyName 'EditionMode' -NotePropertyValue $editionSelection.Mode -Force
    $Settings.Edition = $editionSelection.Name
    return $Settings
}

function New-WinMintBuildProfileFromWizardSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$SettingsJson,
        [switch]$IncludeSecrets
    )

    $settings = $SettingsJson | ConvertFrom-Json
    Assert-WinMintWizardSettings -Settings $settings

    $resolvedSettings = Resolve-WinMintWizardProfileSettings -Settings $settings
    $buildProfile = New-WinMintBuildProfileFromSettings -Settings $resolvedSettings -IncludeSecrets:$IncludeSecrets
    Assert-WinMintBuildProfile -BuildProfile $buildProfile
    return $buildProfile
}

function Save-WinMintBuildProfileFromWizardSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$SettingsPath,
        [Parameter(Mandatory)][string]$OutputPath,
        [switch]$IncludeSecrets
    )

    $settingsJson = Get-Content -LiteralPath $SettingsPath -Raw
    $parsed = $settingsJson | ConvertFrom-Json
    if ($parsed.PSObject.Properties['schemaVersion'] -and [int]$parsed.schemaVersion -eq 4) {
        Assert-WinMintBuildProfile -BuildProfile $parsed
        Save-WinMintBuildProfile -BuildProfile $parsed -Path $OutputPath
        return
    }

    $buildProfile = New-WinMintBuildProfileFromWizardSettings `
        -RepositoryRoot $RepositoryRoot `
        -SettingsJson $settingsJson `
        -IncludeSecrets:$IncludeSecrets

    Save-WinMintBuildProfile -BuildProfile $buildProfile -Path $OutputPath
}
