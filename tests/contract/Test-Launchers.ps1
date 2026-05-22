#Requires -Version 7.3
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:WinMintRepositoryRoot = $root
. (Join-Path $root 'src\engine\Core.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
function Add-LauncherFailure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
    Write-Error $Message -ErrorAction Continue
}

$bootstrap = Get-Content -LiteralPath (Get-WinMintPath -Name RepoRoot -ChildPath 'winmint.ps1') -Raw
if ($bootstrap -notmatch '\[string\]\$Mode = ''Gui''') {
    Add-LauncherFailure 'Default bootstrap mode must be Gui.'
}
if ($bootstrap -notmatch '''Gui''\s*\{\s*\$guiScript\s*\}') {
    Add-LauncherFailure 'Gui launch mode must use the packaged GUI launcher.'
}
if ($bootstrap -notmatch "'Headless'\s*\{\s*Find-WinMintCliScript") {
    Add-LauncherFailure 'Headless launch mode must resolve WinMint-CLI.ps1.'
}
if ($bootstrap -notmatch "'LegacyUi'\s*\{\s*Find-WinMintLegacyUiScript") {
    Add-LauncherFailure 'LegacyUi launch mode must resolve WinMint-LegacyUI.ps1.'
}

foreach ($pathName in @('WinMint-GUI.ps1', 'WinMint-LegacyUI.ps1')) {
    if (-not (Test-Path -LiteralPath (Get-WinMintPath -Name RepoRoot -ChildPath $pathName) -PathType Leaf)) {
        Add-LauncherFailure "Missing launcher: $pathName"
    }
}

$guiLauncher = Get-Content -LiteralPath (Get-WinMintPath -Name RepoRoot -ChildPath 'WinMint-GUI.ps1') -Raw
if ($guiLauncher -notmatch 'Get-WinMintPath -Name GuiBinary') {
    Add-LauncherFailure 'WinMint-GUI.ps1 must resolve the packaged GUI binary through Get-WinMintPath.'
}

$legacyEntry = Get-Content -LiteralPath (Get-WinMintPath -Name LegacyUiEntry) -Raw
if ($legacyEntry -notmatch 'while \(-not \[string\]::IsNullOrWhiteSpace\(\$candidateRoot\)\)') {
    Add-LauncherFailure 'Legacy WPF app entry must walk upward to find src\engine\Core.ps1.'
}

if ($failures.Count -gt 0) {
    throw "Launcher contract failed with $($failures.Count) error(s)."
}
Write-Host 'Launcher contract passed.'
