@{
    RootModule = 'WinMint.FirstLogon.psm1'
    ModuleVersion = '0.1.0'
    GUID = '0706ed24-5d92-40ec-8a5c-7a901307dd06'
    PowerShellVersion = '7.6'
    FunctionsToExport = @(
        'Resolve-AgentPowerShellHost',
        'Save-AgentState',
        'Set-AgentStateValue',
        'Get-WinMintAgentModuleCatalog',
        'New-WinMintAgentRuntimeStepPlan',
        'Get-WinMintAgentLauncherKeyPlan',
        'Invoke-WinMintAgentManifestToolSelection',
        'Invoke-AgentProfileModule'
    )
}
