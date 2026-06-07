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

foreach ($path in @($guiIntentPath, $guiStatePath, $coreProfilePath, $bridgePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Required UI contract file is missing: $path"
    }
}

if ($failures.Count -eq 0) {
    $guiIntent = Get-Content -LiteralPath $guiIntentPath -Raw
    $guiState = Get-Content -LiteralPath $guiStatePath -Raw
    $coreProfile = Get-Content -LiteralPath $coreProfilePath -Raw
    $bridge = Get-Content -LiteralPath $bridgePath -Raw

    Assert-Text $guiIntent 'winmint_core::profile' 'GPUI intent module must delegate reusable contract shaping to winmint-core.'
    Assert-Text $coreProfile 'pub struct KeepFlags' 'winmint-core must define the keep-flag intent inputs.'
    Assert-Text $coreProfile 'pub fn build_ui_intent' 'winmint-core must expose the typed UI intent builder.'
    Assert-Text $coreProfile 'fn ui_intent_serializes_to_the_exact_bridge_contract_keys' 'winmint-core must test the bridge contract key set.'
    Assert-Text $bridge 'Assert-WinMintUiBridgeSettings' 'PowerShell bridge must keep a boundary assertion before engine profile creation.'

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
