#Requires -Version 7.3
[CmdletBinding()]
param(
    [switch]$SkipAnalyzer,
    [switch]$RunAnalyzer,
    [switch]$RunIntegration
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$errors = [System.Collections.Generic.List[string]]::new()

if ($SkipAnalyzer -and $RunAnalyzer) {
    throw 'Use either -SkipAnalyzer or -RunAnalyzer, not both.'
}

$moduleNames = @(
    'Core.ps1',
    'Repository.ps1',
    'JsonSchema.ps1',
    'Assets.ps1',
    'Schemas.ps1'
)

foreach ($moduleName in $moduleNames) {
    $modulePath = Join-Path $PSScriptRoot "Modules\$moduleName"
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        throw "Validation module is missing: $modulePath"
    }
    . $modulePath
}

$validationSteps = [ordered]@{
    'Repository hygiene' = { Test-RepositoryHygiene }
    'Required assets' = {
        Test-RequiredAssets
        Test-DuplicateLargeAssets
    }
    'Preset payloads' = {
        Test-WindhawkPresetPayload
        Test-YasbPresetPayload
        Test-KomorebiPresetPayload
    }
    'Package manifest' = { Test-PackageManifestArchitecture }
    'JSON schemas' = {
        Test-BuildProfileSchema
        Test-BuildManifestSchema
        Test-AgentStateSchema
    }
    'Static source guards' = {
        Test-DismArgumentQuoting
        Test-RegistryTweakStrictModeAccess
    }
    'PowerShell parser' = { Test-PowerShellParser }
    'XML files' = {
        Test-XmlFile -Path (Join-Path $root 'src\WinWS.UI\Views\MainWindow.xaml') -Kind 'XAML'
        Test-XmlFile -Path (Join-Path $root 'src\WinWS.Agent\Start-WinWSFirstLogonUI.xaml') -Kind 'FirstLogon UI XAML'
        Test-XmlFile -Path (Join-Path $root 'config\autounattend.xml') -Kind 'autounattend.xml'
    }
    'JSON files' = {
        Get-ChildItem -LiteralPath (Join-Path $root 'config') -Filter '*.json' |
            ForEach-Object { Test-JsonFile -Path $_.FullName }
        Get-ChildItem -LiteralPath (Join-Path $root 'schemas') -Filter '*.json' -ErrorAction SilentlyContinue |
            ForEach-Object { Test-JsonFile -Path $_.FullName }
        Test-JsonFile -Path (Join-Path $root 'src\WinWS.Agent\BuildProfile.json')
    }
    'PSScriptAnalyzer' = { Invoke-AnalyzerIfAvailable }
    'Optional integration' = {
        if ($RunIntegration) {
            & (Join-Path $root 'scripts\test\Test-Integration.ps1') -RunIsoDryRun
        }
        else {
            Write-Host 'Skipping integration tests. Use -RunIntegration to opt in.'
        }
    }
}

foreach ($step in $validationSteps.GetEnumerator()) {
    Invoke-ValidationStep -Name $step.Key -ScriptBlock $step.Value
}

if ($errors.Count -gt 0) {
    throw "Validation failed with $($errors.Count) error(s)."
}
Write-Host 'Validation passed.'
