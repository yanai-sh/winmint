#Requires -Version 7.6
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)

    $failures.Add($Message) | Out-Null
    Write-Error $Message -ErrorAction Continue
}

function Assert-Text {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -notmatch $Pattern) { Add-Failure $Message }
}

function ConvertTo-WinMintTestJson {
    param([Parameter(Mandatory)]$Value)

    $Value | ConvertTo-Json -Depth 16 -Compress
}

function Copy-WinMintWizardSettingsFixture {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Fixture)

    $copy = [ordered]@{}
    foreach ($key in $Fixture.Keys) {
        $copy[$key] = $Fixture[$key]
    }
    return $copy
}

function Assert-WizardSettingsValidation {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Fixture,
        [Parameter(Mandatory)][bool]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    $settings = $Fixture | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $passed = $true
    try {
        Assert-WinMintWizardSettings -Settings $settings
    }
    catch {
        $passed = $false
    }
    if ($passed -ne $Expected) {
        Add-Failure $Message
    }
}

function Assert-SequenceEqual {
    param(
        [string[]]$Actual,
        [string[]]$Expected,
        [string]$Message
    )

    if (($Actual -join "`n") -ne ($Expected -join "`n")) {
        Add-Failure "$Message Actual: [$($Actual -join ', ')] Expected: [$($Expected -join ', ')]"
    }
}

$wizardHtmlPath = Join-Path $root 'assets\runtime\setup\setup-shell\wizard.html'
$wizardJsPath = Join-Path $root 'assets\runtime\setup\setup-shell\wizard.js'
$appOptionsPath = Join-Path $root 'apps\setup-shell\AppOptions.cs'
$wizardBridgePath = Join-Path $root 'apps\setup-shell-web\WizardBridge.cs'
$releaseManifestPath = Join-Path $root 'config\release-manifest.json'
$bridgePath = Join-Path $root 'tools\ui-bridge\New-UiBuildProfile.ps1'
$profileOptionCatalogPath = Join-Path $root 'src\runtime\image\Private\Config\OptionCatalog.ps1'
$profileAuthoringPath = Join-Path $root 'src\runtime\image\Private\Config\ProfileAuthoring.ps1'
$pipelineConsolePath = Join-Path $root 'src\runtime\image\Private\Pipeline.Console.ps1'
$reviewConsolePath = Join-Path $root 'src\runtime\image\Private\Console\Review.ps1'

foreach ($path in @($wizardHtmlPath, $wizardJsPath, $appOptionsPath, $wizardBridgePath, $bridgePath, $profileOptionCatalogPath, $profileAuthoringPath, $pipelineConsolePath, $reviewConsolePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Required UI contract file is missing: $path"
    }
}

if ($failures.Count -eq 0) {
    $wizardHtml = Get-Content -LiteralPath $wizardHtmlPath -Raw
    $wizardJs = Get-Content -LiteralPath $wizardJsPath -Raw
    $appOptions = Get-Content -LiteralPath $appOptionsPath -Raw
    $wizardBridge = Get-Content -LiteralPath $wizardBridgePath -Raw
    $releaseManifest = Get-Content -LiteralPath $releaseManifestPath -Raw
    $bridge = Get-Content -LiteralPath $bridgePath -Raw
    $profileOptionCatalog = Get-Content -LiteralPath $profileOptionCatalogPath -Raw
    $profileAuthoring = Get-Content -LiteralPath $profileAuthoringPath -Raw
    $pipelineConsole = Get-Content -LiteralPath $pipelineConsolePath -Raw
    $reviewConsole = Get-Content -LiteralPath $reviewConsolePath -Raw

    Assert-Text $wizardHtml 'wizard.js' 'Build wizard HTML must load wizard.js.'
    Assert-Text $wizardJs 'buildWizardSettings' 'Build wizard JS must emit wizard settings through buildWizardSettings().'
    Assert-Text $wizardJs 'saveWizardSettings' 'Build wizard JS must persist wizard settings through the host bridge.'
    Assert-Text $wizardJs 'KeepGaming' 'Build wizard JS must expose keep-flag intent fields.'
    Assert-Text $wizardJs 'InstallWindhawk' 'Build wizard JS must expose shell layer intent fields.'
    Assert-Text $wizardJs 'generateProfile' 'Build wizard JS must call generateProfile through the host bridge.'
    Assert-Text $wizardJs 'startDryRun' 'Build wizard JS must call startDryRun through the host bridge.'
    Assert-Text $appOptions '--wizard' 'AppOptions must parse --wizard for the build wizard host.'
    Assert-Text $appOptions '--repo-root' 'AppOptions must parse --repo-root for the build wizard host.'
    Assert-Text $wizardBridge 'RunBridgeScript' 'Wizard bridge must spawn PowerShell ui-bridge scripts.'
    Assert-Text $releaseManifest 'tools/ui-bridge' 'Release manifest must ship tools/ui-bridge for the wizard host.'
    Assert-Text $profileOptionCatalog 'function Get-WinMintOptionCatalog' 'PowerShell backend must expose an option catalog.'
    Assert-Text $profileOptionCatalog 'WslDistro' 'PowerShell option catalog must expose WSL profile tokens.'
    Assert-Text $bridge 'Save-WinMintBuildProfileFromWizardSettings' 'PowerShell bridge must delegate wizard settings profile generation to the backend authoring module.'
    Assert-Text $profileAuthoring 'Assert-WinMintWizardSettings' 'Profile authoring module must validate wizard settings before engine profile creation.'
    Assert-Text (Get-Content -LiteralPath (Join-Path $root 'tools\ui-bridge\Start-UiBuildFromProfile.ps1') -Raw) 'Ok\s*=' 'UI build invocation bridge should emit a normalized JSON result.'
    . $profileOptionCatalogPath
    . $profileAuthoringPath
    $validWizardSettings = [ordered]@{
        Profile              = 'WinMint'
        KeepEdge             = $false
        KeepGaming           = $false
        KeepCopilot          = $false
        ISOPath              = 'C:\iso\win.iso'
        Architecture         = 'arm64'
        ComputerName         = 'WinMint'
        AccountName          = 'dev'
        AccountMode          = 'Local'
        TargetDevice         = 'DifferentPC'
        FormFactor           = 'Auto'
        Edition              = 'Host'
        DriverSource         = 'None'
        DriverPath           = ''
        InstallWindhawk      = $true
        InstallYasb          = $true
        InstallKomorebi      = $true
        InstallNilesoft      = $false
        Editors              = @('cursor', 'neovim')
        Browsers             = @('brave', 'edge')
        Wsl2Distros          = @('Ubuntu', 'FedoraLinux')
        PrivLocation         = $true
        TweakHardwareBypass  = $false
        TweakDmaInterop      = $true
    }
    Assert-WizardSettingsValidation -Fixture $validWizardSettings -Expected $true -Message 'Wizard settings validation should accept the bridge fixture.'
    $unknownKeySettings = Copy-WinMintWizardSettingsFixture -Fixture $validWizardSettings
    $unknownKeySettings['Unexpected'] = $true
    Assert-WizardSettingsValidation -Fixture $unknownKeySettings -Expected $false -Message 'Wizard settings validation should reject unknown keys.'
    $invalidEditorSettings = Copy-WinMintWizardSettingsFixture -Fixture $validWizardSettings
    $invalidEditorSettings['Editors'] = @('cursor', 'unknown-editor')
    Assert-WizardSettingsValidation -Fixture $invalidEditorSettings -Expected $false -Message 'Wizard settings validation should reject unknown editor ids.'
    $invalidBrowserSettings = Copy-WinMintWizardSettingsFixture -Fixture $validWizardSettings
    $invalidBrowserSettings['Browsers'] = @('unknown-browser')
    Assert-WizardSettingsValidation -Fixture $invalidBrowserSettings -Expected $false -Message 'Wizard settings validation should reject unknown browser ids.'
    $invalidWslSettings = Copy-WinMintWizardSettingsFixture -Fixture $validWizardSettings
    $invalidWslSettings['Wsl2Distros'] = @('Fedora')
    Assert-WizardSettingsValidation -Fixture $invalidWslSettings -Expected $false -Message 'Wizard settings validation should reject non-profile WSL distro tokens.'
    $invalidFormFactorSettings = Copy-WinMintWizardSettingsFixture -Fixture $validWizardSettings
    $invalidFormFactorSettings['FormFactor'] = 'Tablet'
    Assert-WizardSettingsValidation -Fixture $invalidFormFactorSettings -Expected $false -Message 'Wizard settings validation should reject unsupported form factors.'
    Assert-Text $pipelineConsole 'InstallNilesoft' 'Interactive console build path must carry the Nilesoft shell option.'
    Assert-Text $pipelineConsole 'Wsl2Distros' 'Interactive console build path must carry WSL distro selections.'
    Assert-Text $reviewConsole 'InstallNilesoft' 'Build summary must surface Nilesoft.'
    Assert-Text $reviewConsole 'WSL distros' 'Build summary must surface the selected WSL distros.'
    Assert-Text (Get-Content -LiteralPath (Join-Path $root 'config\packages.json') -Raw) '(?s)"displayName"\s*:\s*"Raycast".*"source"\s*:\s*"store"' 'Raycast catalog entry must use the Store source.'
    Assert-Text (Get-Content -LiteralPath (Join-Path $root 'config\packages.json') -Raw) '(?s)"everything-arm64-beta".*"source"\s*:\s*"direct".*"sha256"\s*:\s*"2D511A33A3494147F921DCB488772125E6CC654E677196AACB0235967A27D2DA"' 'ARM64 Everything beta must be a hash-pinned direct package.'
    Assert-Text (Get-Content -LiteralPath (Join-Path $root 'src\runtime\image\Private\InstallPlan.ps1') -Raw) 'everything-arm64-beta' 'Install plan must route ARM64 Raycast file search to the pinned native Everything package.'
    Assert-Text (Get-Content -LiteralPath (Join-Path $root 'config\packages.json') -Raw) '(?s)"displayName"\s*:\s*"MinGit".*"source"\s*:\s*"scoop"' 'MinGit must be Scoop-owned.'
    Assert-Text (Get-Content -LiteralPath (Join-Path $root 'config\packages.json') -Raw) '(?s)"displayName"\s*:\s*"Starship".*"source"\s*:\s*"scoop"' 'Starship must be Scoop-owned.'
    Assert-Text (Get-Content -LiteralPath (Join-Path $root 'config\packages.json') -Raw) '(?s)"displayName"\s*:\s*"Neovim".*"source"\s*:\s*"scoop"' 'Neovim must be Scoop-owned.'
    Assert-Text (Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Agent.Install.ps1') -Raw) "--source'.*winget" 'Winget installs must explicitly declare the winget source.'
    Assert-Text (Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Agent.Install.ps1') -Raw) "--source'.*msstore" 'Store-backed installs must explicitly declare the msstore source.'
    Assert-Text (Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Agent.Install.ps1') -Raw) 'target architecture is arm64' 'Scoop installs should explicitly log ARM64 native-package preference.'
    $packageManagerModule = Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Modules\PackageManagers.ps1') -Raw
    Assert-Text $packageManagerModule 'preset''?,\s*''?nerd-font-symbols' 'Starship should be configured with the nerd-font-symbols preset.'
    Assert-Text $packageManagerModule 'Cascadia Code NF' 'Starship terminal setup should document the Cascadia Code NF terminal font.'
    $terminalSettings = Get-Content -LiteralPath (Join-Path $root 'assets\runtime\windows-terminal\settings.json') -Raw
    Assert-Text $terminalSettings '"colorScheme"\s*:\s*"One Half Dark"' 'Windows Terminal should default to One Half Dark.'
    Assert-Text $terminalSettings '"bellStyle"\s*:\s*"none"' 'Windows Terminal audible bell should be disabled by default.'
    Assert-Text $terminalSettings '"centerOnLaunch"\s*:\s*true' 'Windows Terminal should be centered on launch by default.'
    $editorsModule = Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Modules\Editors.ps1') -Raw
    Assert-Text $packageManagerModule 'Install-AgentTool -Tool \$tool -State \$State' 'Editor/browser selections should install through their package-manager owner from packages.json.'
    Assert-Text $editorsModule 'Invoke-WinMintAgentManifestToolSelection' 'Editors should delegate package selection to the package manager module.'
    if ($editorsModule -match 'nvim-win-arm64\.zip|Neovim\.Neovim|nvim-qt\.exe') {
        Add-Failure 'Neovim must no longer use the old GitHub ZIP/winget special case.'
    }

    $removedTerms = @(
        ('WinMint-Legacy' + 'UI'),
        ('legacy' + '-wpf'),
        ('Wpf' + '.Ui')
    )
    foreach ($removed in $removedTerms) {
        foreach ($pair in @(
                @{ Name = 'Wizard JS'; Text = $wizardJs },
                @{ Name = 'UI bridge'; Text = $bridge }
            )) {
            if ($pair.Text -match [regex]::Escape($removed)) {
                Add-Failure "$($pair.Name) must not reference removed compatibility surface '$removed'."
            }
        }
    }
}

if ($failures.Count -gt 0) {
    throw "UI contract spine tests failed with $($failures.Count) failure(s)."
}

Write-Host 'UI contract spine tests passed.'

