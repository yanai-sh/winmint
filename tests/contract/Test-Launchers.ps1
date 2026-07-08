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
if ($bootstrap -notmatch 'Find-WinMintWizardHost') {
    Add-LauncherFailure 'Gui launch mode must resolve the packaged WebView2 wizard host.'
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
if ($guiLauncher -notmatch 'Get-WinMintSetupShellHostPath') {
    Add-LauncherFailure 'WinMint-GUI.ps1 must resolve the WebView2 wizard host via Get-WinMintSetupShellHostPath.'
}
$cliLauncher = Get-Content -LiteralPath (Get-WinMintPath -Name RepoRoot -ChildPath 'WinMint-CLI.ps1') -Raw
if ($cliLauncher -notmatch 'WinMint\.Bootstrap\\WinMint\.Bootstrap\.psd1') {
    Add-LauncherFailure 'WinMint-CLI.ps1 must import the WinMint.Bootstrap module manifest.'
}

$arch = Get-WinMintHostSetupShellBinArch
$wizardExe = Join-Path $root "assets\runtime\setup\setup-shell\bin\$arch\WinMintSetupShell.exe"
$nativeExe = Join-Path $root "assets\runtime\setup\setup-shell\bin\$arch\WinMintSetupShell.Native.exe"
if (-not (Test-Path -LiteralPath $wizardExe -PathType Leaf)) {
    Add-LauncherFailure "WebView2 wizard host missing: $wizardExe"
}
if (-not (Test-Path -LiteralPath $nativeExe -PathType Leaf)) {
    Add-LauncherFailure "Native splash host missing: $nativeExe"
}

$removedLauncherPattern = ('Legacy' + 'Ui|Find-WinMintLegacy' + 'UiScript|WinMint-Legacy' + 'UI')
if ($bootstrap -match $removedLauncherPattern) {
    Add-LauncherFailure 'Bootstrap must not expose the removed compatibility launcher path.'
}

if ($failures.Count -gt 0) {
    throw "Launcher contract failed with $($failures.Count) error(s)."
}
Write-Host 'Launcher contract passed.'
