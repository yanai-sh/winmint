#Requires -Version 7.3
<#
.SYNOPSIS
  Builds a WinMint BuildProfile JSON file from UI settings JSON.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$SettingsPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [switch]$IncludeSecrets
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-WinMintUiBridgeSettings {
    param([Parameter(Mandatory)][object]$Settings)

    $required = @(
        'Profile',
        'KeepEdge',
        'KeepGaming',
        'KeepCopilot',
        'ISOPath',
        'Architecture',
        'ComputerName',
        'AccountName',
        'AccountMode',
        'TargetDevice',
        'Edition',
        'DriverSource',
        'InstallWindhawk',
        'InstallYasb',
        'InstallKomorebi',
        'Editors',
        'Wsl2Distros'
    )

    foreach ($name in $required) {
        if (-not ($Settings.PSObject.Properties.Name -contains $name)) {
            throw "UI bridge settings missing required field '$name'."
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$Settings.Architecture)) {
        throw 'UI bridge settings must include Architecture.'
    }
}

$script:WinMintRepositoryRoot = $RepositoryRoot
. (Join-Path $RepositoryRoot 'src\engine\Core.ps1')
$engine = Get-WinMintPath -Name EngineEntry
. $engine
Initialize-WinMintEngine -RepositoryRoot $RepositoryRoot

$settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
Assert-WinMintUiBridgeSettings -Settings $settings
# Resolve the GUI's edition token (Host/Home/Pro/.../exact) into the concrete
# editionMode/edition the engine consumes, reusing the resolver the CLI uses.
$editionSelection = Resolve-WinMintEditionSelection -Edition ([string]$settings.Edition) -EditionSpecified $true
$settings | Add-Member -NotePropertyName 'EditionMode' -NotePropertyValue $editionSelection.Mode -Force
$settings.Edition = $editionSelection.Name
$profile = New-WinMintBuildProfileFromSettings -Settings $settings -IncludeSecrets:$IncludeSecrets
$null = Save-WinMintBuildProfile -BuildProfile $profile -Path $OutputPath
