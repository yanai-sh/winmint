#Requires -Version 7.3

function Assert-WinMintUiIntentSettings {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$SettingsJson,
        [Parameter(Mandatory)][object]$Settings
    )

    $schemaPath = Join-Path $RepositoryRoot 'schemas\winmint.uiintent.schema.json'
    if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
        throw "UI intent schema not found: $schemaPath"
    }

    $schemaJson = Get-Content -LiteralPath $schemaPath -Raw
    if (-not (Test-Json -Json $SettingsJson -Schema $schemaJson)) {
        throw "UI bridge settings do not match schemas\winmint.uiintent.schema.json."
    }

    if ([string]::IsNullOrWhiteSpace([string]$Settings.Architecture)) {
        throw 'UI bridge settings must include Architecture.'
    }
    $uiArchitectureOptions = @(Get-WinMintOptionValues -Name UiArchitecture)
    if ($uiArchitectureOptions -notcontains [string]$Settings.Architecture) {
        throw "UI bridge settings Architecture must be one of: $($uiArchitectureOptions -join ', ')."
    }
    if ([string]$Settings.Architecture -eq 'Unknown') {
        throw 'UI bridge settings must include a resolved Architecture before profile generation.'
    }
}

function Resolve-WinMintUiIntentProfileSettings {
    param(
        [Parameter(Mandatory)][object]$Settings
    )

    $editionSelection = Resolve-WinMintEditionSelection -Edition ([string]$Settings.Edition) -EditionSpecified $true
    $Settings | Add-Member -NotePropertyName 'EditionMode' -NotePropertyValue $editionSelection.Mode -Force
    $Settings.Edition = $editionSelection.Name
    return $Settings
}

function New-WinMintBuildProfileFromUiIntent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$SettingsJson,
        [switch]$IncludeSecrets
    )

    $settings = $SettingsJson | ConvertFrom-Json
    Assert-WinMintUiIntentSettings `
        -RepositoryRoot $RepositoryRoot `
        -SettingsJson $SettingsJson `
        -Settings $settings

    $resolvedSettings = Resolve-WinMintUiIntentProfileSettings -Settings $settings
    $profile = New-WinMintBuildProfileFromSettings -Settings $resolvedSettings -IncludeSecrets:$IncludeSecrets
    Assert-WinMintBuildProfile -BuildProfile $profile
    return $profile
}

function Save-WinMintBuildProfileFromUiIntent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$SettingsPath,
        [Parameter(Mandatory)][string]$OutputPath,
        [switch]$IncludeSecrets
    )

    $settingsJson = Get-Content -LiteralPath $SettingsPath -Raw
    $profile = New-WinMintBuildProfileFromUiIntent `
        -RepositoryRoot $RepositoryRoot `
        -SettingsJson $settingsJson `
        -IncludeSecrets:$IncludeSecrets

    Save-WinMintBuildProfile -BuildProfile $profile -Path $OutputPath
}
