@{
    RootModule = 'WinMint.Profile.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'c690e7fa-f968-4b4f-9b03-f7ad6dad67c0'
    PowerShellVersion = '7.6'
    FunctionsToExport = @(
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
}
