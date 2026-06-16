@{
    RootModule = 'WinMint.Catalog.psm1'
    ModuleVersion = '0.1.0'
    GUID = '31c47a02-54ec-4250-8e80-5003a1d52226'
    PowerShellVersion = '7.6'
    FunctionsToExport = @(
        'Get-WinMintAppxRemovalCatalog',
        'Get-WinMintAiRemovalCatalog',
        'New-WinMintAiRemovalConfig',
        'Get-WinMintRegistryTweakValue',
        'Get-WinMintSelectedRegistryTweaks',
        'New-WinMintTweakContext',
        'Get-WinMintAppxBloatwareCategories'
    )
}
