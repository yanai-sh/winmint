@{
    RootModule = 'WinMint.Setup.psm1'
    ModuleVersion = '0.1.0'
    GUID = '22ac3cb0-9daa-4ca2-a378-918577dcf2ea'
    PowerShellVersion = '7.6'
    FunctionsToExport = @(
        'Get-WinMintSetupActionCatalog',
        'New-WinMintSetupProfile',
        'New-WinMintSetupPlan',
        'Install-Autounattend'
    )
}
