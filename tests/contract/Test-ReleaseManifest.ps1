#Requires -Version 7.3
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:WinMintRepositoryRoot = $root
. (Join-Path $root 'src\WinMint\Core.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
function Add-ReleaseManifestFailure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
    Write-Error $Message -ErrorAction Continue
}

$manifest = Get-Content -LiteralPath (Get-WinMintPath -Name Config -ChildPath 'release-manifest.json') -Raw | ConvertFrom-Json
$include = @($manifest.include)
$exclude = @($manifest.exclude)

foreach ($required in @(
    'WinMint-CLI.ps1',
    'WinMint-GUI.ps1',
    'WinMint-LegacyUI.ps1',
    'winmint.ps1',
    'apps/WinMint.GPUI/bin/WinMint-GUI.exe',
    'apps/WinMint.LegacyWpf'
)) {
    if ($include -notcontains $required) {
        Add-ReleaseManifestFailure "Release manifest missing include: $required"
    }
}

foreach ($forbidden in @('apps', 'tools', 'WinMint-UI.ps1')) {
    if ($include -contains $forbidden) {
        Add-ReleaseManifestFailure "Release manifest must not include runtime path: $forbidden"
    }
}

foreach ($requiredExclude in @('tools', '**/target', 'output', 'dist')) {
    if ($exclude -notcontains $requiredExclude) {
        Add-ReleaseManifestFailure "Release manifest missing exclude: $requiredExclude"
    }
}

if ($failures.Count -gt 0) {
    throw "Release manifest contract failed with $($failures.Count) error(s)."
}
Write-Host 'Release manifest contract passed.'
