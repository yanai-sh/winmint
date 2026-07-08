#Requires -Version 5.1
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

Import-Module (Join-Path $RepositoryRoot 'src\runtime\modules\WinMint.Bootstrap\WinMint.Bootstrap.psd1') -Force
$bootstrapArgs = @(
    '-RepositoryRoot', $RepositoryRoot,
    '-SettingsPath', $SettingsPath,
    '-OutputPath', $OutputPath
)
if ($IncludeSecrets) { $bootstrapArgs += '-IncludeSecrets' }
$bootstrap = Invoke-WinMintRuntimeBootstrap -Entrypoint $PSCommandPath -Arguments $bootstrapArgs
if ($bootstrap.Relaunched) {
    exit $bootstrap.ExitCode
}

$script:WinMintRepositoryRoot = $RepositoryRoot
Import-Module (Join-Path $RepositoryRoot 'src\runtime\modules\WinMint.Profile\WinMint.Profile.psd1') -Force

$null = Save-WinMintBuildProfileFromWizardSettings `
    -RepositoryRoot $RepositoryRoot `
    -SettingsPath $SettingsPath `
    -OutputPath $OutputPath `
    -IncludeSecrets:$IncludeSecrets
