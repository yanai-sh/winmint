#Requires -Version 7.6
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:WinMintRepositoryRoot = $root
. (Join-Path $root 'src\runtime\image\Core.ps1')

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
if ($bootstrap -notmatch 'Find-WinMintGuiExecutable') {
    Add-LauncherFailure 'Gui launch mode must resolve the packaged GUI executable.'
}
if ($bootstrap -notmatch '\$entryScript\s*=\s*Find-WinMintCliScript') {
    Add-LauncherFailure 'Headless launch mode must resolve WinMint-CLI.ps1.'
}

foreach ($pathName in @('WinMint-GUI.ps1')) {
    if (-not (Test-Path -LiteralPath (Get-WinMintPath -Name RepoRoot -ChildPath $pathName) -PathType Leaf)) {
        Add-LauncherFailure "Missing launcher: $pathName"
    }
}

$guiLauncher = Get-Content -LiteralPath (Get-WinMintPath -Name RepoRoot -ChildPath 'WinMint-GUI.ps1') -Raw
if ($guiLauncher -notmatch 'WinMint\.Bootstrap\\WinMint\.Bootstrap\.psd1') {
    Add-LauncherFailure 'WinMint-GUI.ps1 must import the WinMint.Bootstrap module manifest.'
}
if ($guiLauncher -notmatch 'Get-WinMintPath -Name GuiBinary') {
    Add-LauncherFailure 'WinMint-GUI.ps1 must resolve the packaged GUI binary through Get-WinMintPath.'
}
$cliLauncher = Get-Content -LiteralPath (Get-WinMintPath -Name RepoRoot -ChildPath 'WinMint-CLI.ps1') -Raw
if ($cliLauncher -notmatch 'WinMint\.Bootstrap\\WinMint\.Bootstrap\.psd1') {
    Add-LauncherFailure 'WinMint-CLI.ps1 must import the WinMint.Bootstrap module manifest.'
}

$removedLauncherPattern = ('Legacy' + 'Ui|Find-WinMintLegacy' + 'UiScript|WinMint-Legacy' + 'UI')
if ($bootstrap -match $removedLauncherPattern) {
    Add-LauncherFailure 'Bootstrap must not expose the removed compatibility launcher path.'
}

if ($failures.Count -gt 0) {
    throw "Launcher contract failed with $($failures.Count) error(s)."
}
Write-Host 'Launcher contract passed.'

