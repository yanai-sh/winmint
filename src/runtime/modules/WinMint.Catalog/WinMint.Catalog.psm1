#Requires -Version 7.6

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'WinMint.ModuleLoader.ps1')
$root = Get-WinMintModuleRepositoryRoot
foreach ($relativePath in @(Get-WinMintRuntimeModuleFileList -Area Catalog)) {
    . (Join-Path $root $relativePath)
}

Export-ModuleMember -Function @(
    'Get-WinMintAppxRemovalCatalog',
    'Get-WinMintAiRemovalCatalog',
    'New-WinMintAiRemovalConfig',
    'Get-WinMintRegistryTweakValue',
    'Get-WinMintSelectedRegistryTweaks',
    'New-WinMintTweakContext',
    'Get-WinMintAppxBloatwareCategories'
)
