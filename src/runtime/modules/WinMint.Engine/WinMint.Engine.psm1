#Requires -Version 7.6

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'WinMint.ModuleLoader.ps1')
$root = Get-WinMintModuleRepositoryRoot
foreach ($relativePath in @(Get-WinMintRuntimeModuleFileList -Area Engine)) {
    . (Join-Path $root $relativePath)
}

Export-ModuleMember -Function @(
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
