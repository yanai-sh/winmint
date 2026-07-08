#Requires -Version 7.6
<#
.SYNOPSIS
    Populate host build payload caches (Nerd Fonts) without running a full ISO build.

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Warm-WinMintBuildCache.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$engineRoot = Join-Path $repoRoot 'src\runtime\image'

. (Join-Path $engineRoot 'Core.ps1')
. (Join-Path $engineRoot 'Private\Manifest.ps1')
. (Join-Path $engineRoot 'Private\Runtime.ps1')
. (Join-Path $engineRoot 'Private\Console\Host.ps1')
Initialize-Spectre
. (Join-Path $engineRoot 'Private\Console\Display.ps1')
function Assert-Win11IsoFileHash {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$Label = '',
        [string]$ExpectedHash = ''
    )
    $hash = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash
    if (-not [string]::IsNullOrWhiteSpace($ExpectedHash) -and $hash -ne $ExpectedHash.ToUpperInvariant()) {
        throw "${Label}SHA256 mismatch. Expected: $ExpectedHash  Got: $hash"
    }
    return $hash
}

. (Join-Path $engineRoot 'Private\PayloadStore.ps1')
. (Join-Path $engineRoot 'Private\IntermediatesCache.ps1')
. (Join-Path $engineRoot 'Private\Image\Assets.ps1')

$fontDir = Join-Path $repoRoot 'assets\runtime\fonts'
$null = New-Item -ItemType Directory -Path $fontDir -Force

Write-Host 'Warming Cascadia Nerd Font cache...'
Sync-NerdFont -FontDir $fontDir

$checks = @(
    @{ Label = 'Cascadia Code font'; Patterns = @('*CascadiaCodeNF-Regular.ttf') }
)
$failures = [System.Collections.Generic.List[string]]::new()
foreach ($check in $checks) {
    $font = $null
    foreach ($pattern in $check.Patterns) {
        $font = Get-ChildItem -LiteralPath $fontDir -Filter $pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($font) { break }
    }
    if ($font) {
        Write-Host "  OK $($check.Label): $($font.Name)"
    }
    else {
        $failures.Add("$($check.Label) is still missing from $fontDir after sync.") | Out-Null
    }
}

if ($failures.Count -gt 0) {
    throw ($failures -join ' ')
}

Write-Host 'Build payload caches are ready under' (Get-WinMintBuildCacheRoot)
