@{
    RootModule = 'WinMint.Reporting.psm1'
    ModuleVersion = '0.1.0'
    GUID = '64bc0270-a7bb-464d-ad88-b52e4e2f024f'
    PowerShellVersion = '7.6'
    FunctionsToExport = @(
        'New-WinMintBuildReport',
        'Save-WinMintBuildReport',
        'Get-WinMintBuildManifest',
        'Initialize-WinMintBuildManifest',
        'Save-WinMintBuildManifest',
        'Clear-WinMintBuildManifest'
    )
}
