#Requires -Version 7.3
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

$guiIntentPath = Join-Path $root 'apps\gui\src\intent.rs'
$guiStatePath = Join-Path $root 'apps\gui\src\state.rs'
$coreProfilePath = Join-Path $root 'crates\winmint-core\src\profile.rs'
$bridgePath = Join-Path $root 'tools\ui-bridge\New-UiBuildProfile.ps1'
$pipelineConsolePath = Join-Path $root 'src\runtime\image\Private\Pipeline.Console.ps1'
$reviewConsolePath = Join-Path $root 'src\runtime\image\Private\Console\Review.ps1'

foreach ($path in @($guiIntentPath, $guiStatePath, $coreProfilePath, $bridgePath, $pipelineConsolePath, $reviewConsolePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Required UI contract file is missing: $path"
    }
}

if ($failures.Count -eq 0) {
    $guiIntent = Get-Content -LiteralPath $guiIntentPath -Raw
    $guiState = Get-Content -LiteralPath $guiStatePath -Raw
    $coreProfile = Get-Content -LiteralPath $coreProfilePath -Raw
    $bridge = Get-Content -LiteralPath $bridgePath -Raw
    $pipelineConsole = Get-Content -LiteralPath $pipelineConsolePath -Raw
    $reviewConsole = Get-Content -LiteralPath $reviewConsolePath -Raw

    Assert-Text $guiIntent 'winmint_core::profile' 'GPUI intent module must delegate reusable contract shaping to winmint-core.'
    Assert-Text $coreProfile 'pub struct KeepFlags' 'winmint-core must define the keep-flag intent inputs.'
    Assert-Text $coreProfile 'pub fn build_ui_intent' 'winmint-core must expose the typed UI intent builder.'
    Assert-Text $coreProfile 'fn ui_intent_serializes_to_the_exact_bridge_contract_keys' 'winmint-core must test the bridge contract key set.'
    Assert-Text $bridge 'Assert-WinMintUiBridgeSettings' 'PowerShell bridge must keep a boundary assertion before engine profile creation.'
    Assert-Text $pipelineConsole 'InstallNilesoft' 'Interactive console build path must carry the Nilesoft shell option.'
    Assert-Text $pipelineConsole 'Wsl2Distros' 'Interactive console build path must carry WSL distro selections.'
    Assert-Text $reviewConsole 'InstallNilesoft' 'Build summary must surface Nilesoft.'
    Assert-Text $reviewConsole 'WSL distros' 'Build summary must surface the selected WSL distros.'
    Assert-Text (Get-Content -LiteralPath (Join-Path $root 'config\packages.json') -Raw) '(?s)"displayName"\s*:\s*"Raycast".*"source"\s*:\s*"store"' 'Raycast catalog entry must use the Store source.'
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
    Assert-Text $editorsModule 'Install-AgentTool -Tool \$tool -State \$State' 'Editors should install through their package-manager owner from packages.json.'
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
                @{ Name = 'winmint-core profile'; Text = $coreProfile },
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
