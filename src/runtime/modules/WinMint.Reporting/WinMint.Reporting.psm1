#Requires -Version 7.6

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'WinMint.ModuleLoader.ps1')
$root = Get-WinMintModuleRepositoryRoot
foreach ($relativePath in @(Get-WinMintRuntimeModuleFileList -Area Reporting)) {
    . (Join-Path $root $relativePath)
}

Export-ModuleMember -Function @(
    'New-WinMintBuildReport',
    'Save-WinMintBuildReport',
    'Get-WinMintBuildManifest',
    'Initialize-WinMintBuildManifest',
    'Save-WinMintBuildManifest',
    'Clear-WinMintBuildManifest'
)
