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

function Copy-WinMintUiIntentFixture {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Fixture)

    $copy = [ordered]@{}
    foreach ($key in $Fixture.Keys) {
        $copy[$key] = $Fixture[$key]
    }
    return $copy
}

function Assert-UiIntentSchemaResult {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Fixture,
        [Parameter(Mandatory)][bool]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    $json = ConvertTo-WinMintTestJson -Value $Fixture
    $actual = Test-Json -Json $json -Schema $script:UiIntentSchema -ErrorAction SilentlyContinue
    if ([bool]$actual -ne $Expected) {
        Add-Failure $Message
    }
}

function Get-UiIntentSchemaEnumValues {
    param(
        [Parameter(Mandatory)]$Schema,
        [Parameter(Mandatory)][string]$PropertyName
    )

    $property = $Schema.properties.$PropertyName
    if ($property.PSObject.Properties['items']) {
        return @($property.items.enum | ForEach-Object { [string]$_ })
    }
    @($property.enum | ForEach-Object { [string]$_ })
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

$guiIntentPath = Join-Path $root 'apps\gui\src\intent.rs'
$guiStatePath = Join-Path $root 'apps\gui\src\state.rs'
$guiOptionsPath = Join-Path $root 'apps\gui\src\options.rs'
$guiBridgePath = Join-Path $root 'apps\gui\src\bridge.rs'
$guiMainPath = Join-Path $root 'apps\gui\src\main.rs'
$guiConfigureScreenPath = Join-Path $root 'apps\gui\src\screens\configure.rs'
$guiBuildScreenPath = Join-Path $root 'apps\gui\src\screens\build.rs'
$guiReviewScreenPath = Join-Path $root 'apps\gui\src\screens\review.rs'
$coreOptionsPath = Join-Path $root 'apps\gui\src\core\options.rs'
$coreProfilePath = Join-Path $root 'apps\gui\src\core\profile.rs'
$bridgePath = Join-Path $root 'tools\ui-bridge\New-UiBuildProfile.ps1'
$profileOptionCatalogPath = Join-Path $root 'src\runtime\image\Private\Config\OptionCatalog.ps1'
$profileAuthoringPath = Join-Path $root 'src\runtime\image\Private\Config\ProfileAuthoring.ps1'
$uiIntentSchemaPath = Join-Path $root 'schemas\winmint.uiintent.schema.json'
$pipelineConsolePath = Join-Path $root 'src\runtime\image\Private\Pipeline.Console.ps1'
$reviewConsolePath = Join-Path $root 'src\runtime\image\Private\Console\Review.ps1'

foreach ($path in @($guiIntentPath, $guiStatePath, $guiOptionsPath, $guiBridgePath, $guiMainPath, $guiConfigureScreenPath, $guiBuildScreenPath, $guiReviewScreenPath, $coreOptionsPath, $coreProfilePath, $bridgePath, $profileOptionCatalogPath, $profileAuthoringPath, $uiIntentSchemaPath, $pipelineConsolePath, $reviewConsolePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Required UI contract file is missing: $path"
    }
}

if ($failures.Count -eq 0) {
    $guiIntent = Get-Content -LiteralPath $guiIntentPath -Raw
    $guiState = Get-Content -LiteralPath $guiStatePath -Raw
    $guiOptions = Get-Content -LiteralPath $guiOptionsPath -Raw
    $guiBridge = Get-Content -LiteralPath $guiBridgePath -Raw
    $guiMain = Get-Content -LiteralPath $guiMainPath -Raw
    $guiConfigureScreen = Get-Content -LiteralPath $guiConfigureScreenPath -Raw
    $guiBuildScreen = Get-Content -LiteralPath $guiBuildScreenPath -Raw
    $guiReviewScreen = Get-Content -LiteralPath $guiReviewScreenPath -Raw
    $coreOptions = Get-Content -LiteralPath $coreOptionsPath -Raw
    $coreProfile = Get-Content -LiteralPath $coreProfilePath -Raw
    $bridge = Get-Content -LiteralPath $bridgePath -Raw
    $profileOptionCatalog = Get-Content -LiteralPath $profileOptionCatalogPath -Raw
    $profileAuthoring = Get-Content -LiteralPath $profileAuthoringPath -Raw
    $uiIntentSchema = Get-Content -LiteralPath $uiIntentSchemaPath -Raw
    $pipelineConsole = Get-Content -LiteralPath $pipelineConsolePath -Raw
    $reviewConsole = Get-Content -LiteralPath $reviewConsolePath -Raw

    Assert-Text $guiIntent 'crate::core::profile' 'GPUI intent module must delegate reusable contract shaping to the GUI core module.'
    Assert-Text $coreOptions 'pub const EDITION_OPTIONS' 'GUI core options must expose UI edition option tokens.'
    Assert-Text $coreOptions 'pub const EDITOR_OPTIONS' 'GUI core options must expose editor option tokens.'
    Assert-Text $coreOptions 'pub const BROWSER_OPTIONS' 'GUI core options must expose browser option tokens.'
    Assert-Text $coreOptions 'pub const WSL_OPTIONS' 'GUI core options must expose WSL option tokens.'
    Assert-Text $profileOptionCatalog 'function Get-WinMintOptionCatalog' 'PowerShell backend must expose an option catalog.'
    Assert-Text $profileOptionCatalog 'WslDistro' 'PowerShell option catalog must expose WSL profile tokens.'
    Assert-Text $guiOptions 'pub const EDITIONS' 'GPUI must expose a display catalog for edition options.'
    Assert-Text $guiOptions 'pub const EDITORS' 'GPUI must expose a display catalog for editor options.'
    Assert-Text $guiOptions 'pub const BROWSERS' 'GPUI must expose a display catalog for browser options.'
    Assert-Text $guiOptions 'crate::core::options' 'GPUI option catalog must reuse core wire tokens.'
    Assert-Text $guiConfigureScreen 'options::EDITIONS' 'Configure screen should render edition options from the catalog.'
    Assert-Text $guiConfigureScreen 'options::BROWSERS' 'Configure screen should render browser options from the catalog.'
    Assert-Text $guiConfigureScreen 'options::EDITORS' 'Configure screen should render editor options from the catalog.'
    Assert-Text $guiConfigureScreen 'options::WSL_DISTROS' 'Configure screen should render WSL options from the catalog.'
    Assert-Text $coreProfile 'pub struct KeepFlags' 'GUI core profile must define the keep-flag intent inputs.'
    Assert-Text $coreProfile 'pub fn build_ui_intent' 'GUI core profile must expose the typed UI intent builder.'
    Assert-Text $coreProfile 'fn ui_intent_serializes_to_the_exact_bridge_contract_keys' 'GUI core profile must test the bridge contract key set.'
    Assert-Text $coreProfile 'fn ui_intent_schema_enums_match_option_tokens' 'GUI core profile tests must compare UI intent enum tokens with the schema.'
    Assert-Text $coreProfile 'winmint\.uiintent\.schema\.json' 'GUI core profile tests must compare UI intent keys with the schema.'
    Assert-Text $bridge 'Save-WinMintBuildProfileFromUiIntent' 'PowerShell bridge must delegate UI intent profile generation to the backend authoring module.'
    Assert-Text $profileAuthoring 'Assert-WinMintUiIntentSettings' 'Profile authoring module must keep an intent assertion before engine profile creation.'
    Assert-Text $profileAuthoring 'winmint\.uiintent\.schema\.json' 'Profile authoring module must read the UI intent schema.'
    Assert-Text $profileAuthoring 'Test-Json' 'Profile authoring module must validate UI intent with the JSON schema.'
    Assert-Text $profileAuthoring 'Get-WinMintOptionValues' 'Profile authoring module must validate intent tokens through the PowerShell option catalog.'
    foreach ($expected in @(
            'enum UiBridgeScript',
            'fn script_path',
            'struct BridgeCommandSpec',
            'struct BridgeCommandOutput',
            'struct BridgeBuildResult',
            'struct BridgeProgressEvent',
            'fn parse_powershell_json',
            'fn parse_powershell_result_json',
            'fn require_powershell_success',
            'pub fn write_ui_intent',
            'pub fn generate_build_profile',
            'pub fn start_build_from_profile',
            'fn profile_generation_command',
            'fn build_invocation_command',
            'fn run_source_probe_with'
        )) {
        Assert-Text $guiBridge ([regex]::Escape($expected)) "Rust GUI bridge should own '$expected'."
    }
    Assert-Text $guiMain 'bridge::write_ui_intent' 'WinMintApp should delegate UI intent persistence to bridge.rs.'
    Assert-Text $guiMain 'bridge::generate_build_profile' 'WinMintApp should generate BuildProfile.json through bridge.rs.'
    Assert-Text $guiMain 'bridge::start_build_from_profile' 'WinMintApp should invoke builds through bridge.rs.'
    if ($guiMain -match 'serde_json::to_string_pretty|fs::write\(&output_path') {
        Add-Failure 'WinMintApp must not serialize or write ui-intent.json directly; bridge.rs owns that IO.'
    }
    Assert-Text $guiBuildScreen 'Generate profile' 'GPUI build screen should expose profile generation.'
    Assert-Text $guiBuildScreen 'Dry run' 'GPUI build screen should expose dry-run invocation.'
    Assert-Text $guiBuildScreen 'Manifest' 'GPUI build screen should surface manifest path.'
    Assert-Text $guiBuildScreen 'BuildDelta' 'GPUI build screen should surface BuildDelta path.'
    Assert-Text $guiBuildScreen 'Report' 'GPUI build screen should surface report path.'
    Assert-Text $guiReviewScreen 'Last status' 'GPUI review screen should surface bridge status.'
    Assert-Text $guiReviewScreen 'Output' 'GPUI review screen should surface build output path.'
    Assert-Text $guiReviewScreen 'BuildDelta' 'GPUI review screen should surface BuildDelta path.'
    Assert-Text $guiReviewScreen 'Progress' 'GPUI review screen should surface last bridge progress.'
    Assert-Text (Get-Content -LiteralPath (Join-Path $root 'tools\ui-bridge\Start-UiBuildFromProfile.ps1') -Raw) 'Ok\s*=' 'UI build invocation bridge should emit a normalized JSON result.'
    Assert-Text (Get-Content -LiteralPath (Join-Path $root 'tools\ui-bridge\Start-UiBuildFromProfile.ps1') -Raw) 'BuildDeltaPath' 'UI build invocation bridge should emit the BuildDelta artifact path.'
    foreach ($screen in @(
            @{ Name = 'Build screen'; Text = $guiBuildScreen },
            @{ Name = 'Review screen'; Text = $guiReviewScreen }
        )) {
        if ($screen.Text -match 'Coming soon') {
            Add-Failure "$($screen.Name) must not regress to a placeholder."
        }
    }
    Assert-Text $uiIntentSchema '"required"\s*:\s*\[' 'UI intent schema must define required bridge keys.'
    Assert-Text $uiIntentSchema '"additionalProperties"\s*:\s*false' 'UI intent schema must reject unknown bridge keys.'
    foreach ($expectedEnumToken in @(
            '"arm64"', '"amd64"', '"x86"', '"Unknown"',
            '"Auto"', '"Laptop"', '"Desktop"',
            '"Host"', '"Home"', '"Pro"', '"Enterprise"', '"Education"', '"SingleLanguage"', '"All"',
            '"cursor"', '"vscode"', '"zed"', '"antigravity"', '"neovim"',
            '"zen-browser"', '"helium"', '"firefox-developer-edition"', '"brave"', '"edge"',
            '"Ubuntu"', '"FedoraLinux"', '"archlinux"', '"NixOS-WSL"', '"pengwin"'
        )) {
        Assert-Text $uiIntentSchema ([regex]::Escape($expectedEnumToken)) "UI intent schema must define enum token $expectedEnumToken."
    }
    . $profileOptionCatalogPath
    $script:UiIntentSchema = $uiIntentSchema
    $uiIntentSchemaObject = $uiIntentSchema | ConvertFrom-Json
    Assert-SequenceEqual -Actual (Get-UiIntentSchemaEnumValues -Schema $uiIntentSchemaObject -PropertyName 'Architecture') -Expected (Get-WinMintOptionValues -Name UiArchitecture) -Message 'UI intent Architecture enum must match the PowerShell option catalog.'
    Assert-SequenceEqual -Actual (Get-UiIntentSchemaEnumValues -Schema $uiIntentSchemaObject -PropertyName 'AccountMode') -Expected (Get-WinMintOptionValues -Name AccountMode) -Message 'UI intent AccountMode enum must match the PowerShell option catalog.'
    Assert-SequenceEqual -Actual (Get-UiIntentSchemaEnumValues -Schema $uiIntentSchemaObject -PropertyName 'TargetDevice') -Expected (Get-WinMintOptionValues -Name TargetDevice) -Message 'UI intent TargetDevice enum must match the PowerShell option catalog.'
    Assert-SequenceEqual -Actual (Get-UiIntentSchemaEnumValues -Schema $uiIntentSchemaObject -PropertyName 'FormFactor') -Expected (Get-WinMintOptionValues -Name FormFactor) -Message 'UI intent FormFactor enum must match the PowerShell option catalog.'
    Assert-SequenceEqual -Actual (Get-UiIntentSchemaEnumValues -Schema $uiIntentSchemaObject -PropertyName 'Edition') -Expected (Get-WinMintOptionValues -Name Edition) -Message 'UI intent Edition enum must match the PowerShell option catalog.'
    Assert-SequenceEqual -Actual (Get-UiIntentSchemaEnumValues -Schema $uiIntentSchemaObject -PropertyName 'DriverSource') -Expected (Get-WinMintOptionValues -Name DriverSource) -Message 'UI intent DriverSource enum must match the PowerShell option catalog.'
    Assert-SequenceEqual -Actual (Get-UiIntentSchemaEnumValues -Schema $uiIntentSchemaObject -PropertyName 'Editors') -Expected (Get-WinMintOptionValues -Name Editor) -Message 'UI intent Editors enum must match the PowerShell option catalog.'
    Assert-SequenceEqual -Actual (Get-UiIntentSchemaEnumValues -Schema $uiIntentSchemaObject -PropertyName 'Browsers') -Expected (Get-WinMintOptionValues -Name Browser) -Message 'UI intent Browsers enum must match the PowerShell option catalog.'
    Assert-SequenceEqual -Actual (Get-UiIntentSchemaEnumValues -Schema $uiIntentSchemaObject -PropertyName 'Wsl2Distros') -Expected (Get-WinMintOptionValues -Name WslDistro) -Message 'UI intent Wsl2Distros enum must match the PowerShell option catalog.'
    $validUiIntent = [ordered]@{
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
    Assert-UiIntentSchemaResult -Fixture $validUiIntent -Expected $true -Message 'UI intent schema should accept the bridge fixture.'
    $unknownKeyIntent = Copy-WinMintUiIntentFixture -Fixture $validUiIntent
    $unknownKeyIntent['Unexpected'] = $true
    Assert-UiIntentSchemaResult -Fixture $unknownKeyIntent -Expected $false -Message 'UI intent schema should reject unknown keys.'
    $invalidEditorIntent = Copy-WinMintUiIntentFixture -Fixture $validUiIntent
    $invalidEditorIntent['Editors'] = @('cursor', 'unknown-editor')
    Assert-UiIntentSchemaResult -Fixture $invalidEditorIntent -Expected $false -Message 'UI intent schema should reject unknown editor ids.'
    $invalidBrowserIntent = Copy-WinMintUiIntentFixture -Fixture $validUiIntent
    $invalidBrowserIntent['Browsers'] = @('unknown-browser')
    Assert-UiIntentSchemaResult -Fixture $invalidBrowserIntent -Expected $false -Message 'UI intent schema should reject unknown browser ids.'
    $invalidWslIntent = Copy-WinMintUiIntentFixture -Fixture $validUiIntent
    $invalidWslIntent['Wsl2Distros'] = @('Fedora')
    Assert-UiIntentSchemaResult -Fixture $invalidWslIntent -Expected $false -Message 'UI intent schema should reject non-profile WSL distro tokens.'
    $invalidFormFactorIntent = Copy-WinMintUiIntentFixture -Fixture $validUiIntent
    $invalidFormFactorIntent['FormFactor'] = 'Tablet'
    Assert-UiIntentSchemaResult -Fixture $invalidFormFactorIntent -Expected $false -Message 'UI intent schema should reject unsupported form factors.'
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
    Assert-Text (Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Agent.Runtime.ps1') -Raw) "--source'.*winget" 'Winget installs must explicitly declare the winget source.'
    Assert-Text (Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Agent.Runtime.ps1') -Raw) "--source'.*msstore" 'Store-backed installs must explicitly declare the msstore source.'
    Assert-Text (Get-Content -LiteralPath (Join-Path $root 'src\runtime\firstlogon\Agent.Runtime.ps1') -Raw) 'target architecture is arm64' 'Scoop installs should explicitly log ARM64 native-package preference.'
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

    Assert-Text $guiState 'pub\s+struct\s+BuildIntent' 'GPUI state must define BuildIntent.'
    foreach ($requiredField in @('architecture', 'computer_name', 'account_name', 'keep', 'edition', 'toolkit', 'desktop_layers')) {
        Assert-Text $guiState "\b$([regex]::Escape($requiredField))\b" "BuildIntent must include '$requiredField'."
    }

    $removedTerms = @(
        ('WinMint-Legacy' + 'UI'),
        ('legacy' + '-wpf'),
        ('Wpf' + '.Ui')
    )
    foreach ($removed in $removedTerms) {
        foreach ($pair in @(
                @{ Name = 'GPUI intent'; Text = $guiIntent },
                @{ Name = 'GPUI state'; Text = $guiState },
                @{ Name = 'GUI core profile'; Text = $coreProfile },
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

