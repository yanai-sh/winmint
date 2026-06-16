#Requires -Version 7.6

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'WinMint.ModuleLoader.ps1')
$root = Get-WinMintModuleRepositoryRoot
foreach ($relativePath in @(Get-WinMintRuntimeModuleFileList -Area Setup)) {
    . (Join-Path $root $relativePath)
}

Export-ModuleMember -Function @(
    'Get-WinMintSetupActionCatalog',
    'New-WinMintSetupProfile',
    'New-WinMintSetupPlan',
    'Install-Autounattend'
)
