@{
    RootModule = 'WinMint.Audit.psm1'
    ModuleVersion = '0.1.0'
    GUID = '70d7bc0a-7db5-4dc7-8c47-f6687f3f44bd'
    PowerShellVersion = '7.6'
    FunctionsToExport = @(
        'Clear-WinMintBuildDeltaCatalog',
        'Get-WinMintBuildDeltaCatalog',
        'New-WinMintBuildDeltaCatalog',
        'Save-WinMintBuildDeltaCatalog'
    )
}
