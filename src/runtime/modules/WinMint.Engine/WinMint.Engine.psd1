@{
    RootModule = 'WinMint.Engine.psm1'
    ModuleVersion = '0.1.0'
    GUID = '0fedab11-b3c3-4f15-b468-6a34407145ab'
    PowerShellVersion = '7.6'
    FunctionsToExport = @(
        'Initialize-WinMintEngine',
        'Invoke-WinMintVerbFunction',
        'Invoke-WinMintBuildCommand',
        'Invoke-WinMintNewProfileCommand',
        'Invoke-WinMintValidateCommand',
        'Invoke-WinMintListCommand',
        'Invoke-WinMintCleanCommand',
        'Show-WinMintCliHelp',
        'New-WinMintBuildConfig',
        'New-WinMintInstallPlan',
        'New-WinMintInstallPlanFromBuildConfig',
        'New-WinMintAgentProfile',
        'New-WinMintSetupProfile',
        'New-WinMintSetupPlan',
        'Start-WinMintBuild',
        'Invoke-WinMintIsoBuild',
        'Invoke-WinMintProfileRun',
        'Invoke-WinMintConsoleBuild',
        'Import-WinMintHeadlessBuildProfile',
        'New-WinMintHeadlessResult',
        'Write-WinMintHeadlessJsonResult',
        'Write-WinMintHeadlessHumanResult'
    )
}
