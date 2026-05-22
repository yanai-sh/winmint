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
        'ProfileGroups',
        'ISOPath',
        'Architecture',
        'ComputerName',
        'AccountName',
        'AccountMode',
        'TargetDevice',
        'EditionMode',
        'DriverSource',
        'DesktopUiDefault',
        'InstallWindhawk',
        'InstallYasb',
        'InstallKomorebi',
        'Editors',
        'Wsl2Distros',
        'RemoveGaming'
    )

    foreach ($name in $required) {
        if (-not ($Settings.PSObject.Properties.Name -contains $name)) {
            throw "UI bridge settings missing required field '$name'."
        }
    }

    $groups = @($Settings.ProfileGroups)
    if ($groups.Count -eq 0 -or $groups -notcontains 'Minimal') {
        throw "UI bridge settings must include ProfileGroups with 'Minimal'."
    }

    foreach ($group in $groups) {
        if ($group -notin @('Minimal', 'Developer', 'CopilotPlus', 'Gaming', 'DesktopUI')) {
            throw "UI bridge settings include unsupported profile group '$group'."
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
$profile = New-WinMintBuildProfileFromSettings -Settings $settings -IncludeSecrets:$IncludeSecrets
$null = Save-WinMintBuildProfile -BuildProfile $profile -Path $OutputPath
