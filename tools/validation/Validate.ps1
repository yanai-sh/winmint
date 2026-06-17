#Requires -Version 7.6
[CmdletBinding()]
param(
    [switch]$SkipAnalyzer,
    [switch]$RunAnalyzer,
    [switch]$RunIntegration,
    [switch]$IncludeGuiBuild,
    [switch]$RunReleaseSmoke
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:WinMintRepositoryRoot = $root
. (Join-Path $root 'src\runtime\image\Core.ps1')
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
        Test-WslTerminalIconQuality
    }
    'Preset payloads' = {
        Test-DesktopPresetManifestContracts
        Test-WindhawkPresetPayload
        Test-YasbPresetPayload
        Test-KomorebiPresetPayload
    }
    'Package manifest' = { Test-PackageManifestArchitecture }
    'JSON schemas' = {
        Test-BuildProfileSchema
        Test-TrackedBuildProfileSchemas
        Test-BuildManifestSchema
        Test-AgentStateSchema
        Test-BuildDeltaSchema
    }
    'Static source guards' = {
        Test-DismArgumentQuoting
        Test-RegistryTweakStrictModeAccess
        Test-LauncherArchitecture
        Test-GuiIdentity
        Test-ReleaseManifestRuntimeSurface
    }
    'Optional GUI build' = {
        Test-GuiBuild -IncludeBuild:$IncludeGuiBuild
    }
    'Optional release smoke' = {
        if ($RunReleaseSmoke) {
            $version = 'v0.0.0-validation'
            & (Get-WinMintPath -Name ReleaseToolsRoot -ChildPath 'New-WinMintReleaseBundle.ps1') -Version $version -SkipGuiBuild
            if ($LASTEXITCODE -ne 0) {
                throw "Release bundle build failed with exit code $LASTEXITCODE."
            }
            $bundle = Join-Path (Get-WinMintPath -Name DistRoot) "WinMint-$version.zip"
            & (Get-WinMintPath -Name ReleaseToolsRoot -ChildPath 'Test-WinMintReleaseLaunch.ps1') -BundlePath $bundle -Version $version
            if ($LASTEXITCODE -ne 0) {
                throw "Release smoke failed with exit code $LASTEXITCODE."
            }
        }
        else {
            Write-Host 'Skipping release smoke. Use -RunReleaseSmoke after building the packaged GUI.'
        }
    }
    'Rust crates' = {
        Test-RustCrates
    }
    'PowerShell parser' = {
        # Get-ValidationPowerShellFile recurses *.ps1 (includes tools\gui, excluded: .git\ output\ dist\).
        Test-PowerShellParser
    }
    'XML files' = {
        Test-XmlFile -Path (Get-WinMintPath -Name ConfigRoot -ChildPath 'autounattend.xml') -Kind 'autounattend.xml'
    }
    'JSON files' = {
        Get-ChildItem -LiteralPath (Get-WinMintPath -Name ConfigRoot) -Filter '*.json' |
            ForEach-Object { Test-JsonFile -Path $_.FullName }
        Get-ChildItem -LiteralPath (Get-WinMintPath -Name SchemasRoot) -Filter '*.json' -ErrorAction SilentlyContinue |
            ForEach-Object { Test-JsonFile -Path $_.FullName }
    }
    'PSScriptAnalyzer' = { Invoke-AnalyzerIfAvailable }
    'Optional integration' = {
        if ($RunIntegration) {
            & (Get-WinMintPath -Name ContractTestsRoot -ChildPath 'Test-Integration.ps1') -RunIsoDryRun
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

