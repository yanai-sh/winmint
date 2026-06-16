#Requires -Version 7.6

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'WinMint.ModuleLoader.ps1')
$root = Get-WinMintModuleRepositoryRoot
foreach ($relativePath in @(Get-WinMintRuntimeModuleFileList -Area Audit)) {
    . (Join-Path $root $relativePath)
}

Export-ModuleMember -Function @(
    'Clear-WinMintBuildDeltaCatalog',
    'Get-WinMintBuildDeltaCatalog',
    'New-WinMintBuildDeltaCatalog',
    'Save-WinMintBuildDeltaCatalog'
)
