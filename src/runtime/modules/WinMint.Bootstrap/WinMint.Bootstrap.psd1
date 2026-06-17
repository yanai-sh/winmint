@{
    RootModule = 'WinMint.Bootstrap.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'c2bd9bd6-6b12-4fb2-8f53-2b930c2d9aa0'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-WinMintMinimumPowerShellVersion',
        'Test-WinMintSupportedPowerShell',
        'Resolve-WinMintPreferredPowerShell',
        'Install-WinMintPowerShellRuntime',
        'Invoke-WinMintRuntimeBootstrap'
    )
}
