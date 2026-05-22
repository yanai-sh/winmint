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
$ctlMainPath = Join-Path $root 'crates\winmintctl\src\main.rs'
$bridgePath = Join-Path $root 'tools\ui-bridge\New-UiBuildProfile.ps1'

foreach ($path in @($guiIntentPath, $guiStatePath, $coreProfilePath, $ctlMainPath, $bridgePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Required UI contract file is missing: $path"
    }
}

if ($failures.Count -eq 0) {
    $guiIntent = Get-Content -LiteralPath $guiIntentPath -Raw
    $guiState = Get-Content -LiteralPath $guiStatePath -Raw
    $coreProfile = Get-Content -LiteralPath $coreProfilePath -Raw
    $ctlMain = Get-Content -LiteralPath $ctlMainPath -Raw
    $bridge = Get-Content -LiteralPath $bridgePath -Raw

    Assert-Text $guiIntent 'winmint_core::profile' 'GPUI intent module must delegate reusable contract shaping to winmint-core.'
    Assert-Text $coreProfile 'pub struct GuiIntentInput' 'winmint-core must define typed GUI intent input.'
    Assert-Text $coreProfile 'fn normalized_profile_groups_minimal_first_and_dedupes' 'winmint-core must test profile group normalization.'
    Assert-Text $coreProfile 'fn gui_intent_input_normalizes_through_shared_builder' 'winmint-core must test typed GUI intent normalization.'
    Assert-Text $ctlMain 'normalize-gui-intent' 'winmintctl must expose GUI intent normalization.'
    Assert-Text $bridge 'Assert-WinMintUiBridgeSettings' 'PowerShell bridge must keep a boundary assertion before engine profile creation.'

    Assert-Text $guiState 'pub\s+struct\s+BuildIntent' 'GPUI state must define BuildIntent.'
    foreach ($requiredField in @('architecture', 'computer_name', 'account_name', 'selected_groups', 'toolkit', 'desktop_layers')) {
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
                @{ Name = 'winmintctl'; Text = $ctlMain },
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
