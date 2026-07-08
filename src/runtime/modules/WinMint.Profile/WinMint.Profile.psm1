#Requires -Version 7.6

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'WinMint.ModuleLoader.ps1')
$root = Get-WinMintModuleRepositoryRoot
foreach ($relativePath in @(Get-WinMintRuntimeModuleFileList -Area Profile)) {
    . (Join-Path $root $relativePath)
}

Export-ModuleMember -Function @(
    'Get-WinMintOptionCatalog',
    'Get-WinMintOptionValues',
    'Get-WinMintProfileSetting',
    'Test-WinMintBuildProfile',
    'Assert-WinMintBuildProfile',
    'Save-WinMintBuildProfile',
    'Save-WinMintBuildProfileFromWizardSettings',
    'Save-WinMintBuildProfileFromUiIntent',
    'New-WinMintBuildProfileFromSettings',
    'New-WinMintHeadlessProfileFromFlags'
)
