#Requires -Version 7.6

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'WinMint.ModuleLoader.ps1')
$root = Get-WinMintModuleRepositoryRoot
foreach ($relativePath in @(Get-WinMintRuntimeModuleFileList -Area FirstLogon)) {
    . (Join-Path $root $relativePath)
}

Export-ModuleMember -Function @(
    'Resolve-AgentPowerShellHost',
    'Save-AgentState',
    'Set-AgentStateValue',
    'Get-WinMintAgentModuleCatalog',
    'New-WinMintAgentRuntimeStepPlan',
    'Get-WinMintAgentLauncherKeyPlan',
    'Invoke-WinMintAgentManifestToolSelection',
    'Invoke-AgentProfileModule'
)
