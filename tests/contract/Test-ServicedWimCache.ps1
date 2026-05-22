#Requires -Version 7.3
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Minimal stubs for log helpers the cache module uses.
function Log { param([string]$m) }
function LogVerbose { param([string]$m) }

. (Join-Path $root 'src\engine\Private\IntermediatesCache.ps1')

# Redirect the build cache root to a sandbox so we never touch the real
# %LOCALAPPDATA%\WinMint\cache on the developer's machine.
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ("winmint-cache-test-" + [Guid]::NewGuid().ToString('n'))
$null = New-Item -ItemType Directory -Path $sandbox -Force
function Get-WinMintBuildCacheRoot { return $sandbox }

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

try {
    $buildConfig = [pscustomobject]@{
        Architecture       = 'arm64'
        EditionMode        = 'TargetLicense'
        Edition            = ''
        AppxPackages       = @('Microsoft.BingNews', 'Microsoft.GetHelp')
        RegistryTweaks     = @('dark-mode', 'developer-qol')
        Features           = @('OpenSSH.Client')
        CursorPackKind     = 'Windows11Modern'
        InputLocale        = '0409:00000409'
        SystemLocale       = 'en-US'
        UILanguage         = 'en-US'
        UILanguageFallback = 'en-US'
        UserLocale         = 'en-US'
        SetupUserLocale    = 'en-US'
        Drivers            = [pscustomobject]@{ Source = 'None'; Path = '' }
    }

    # Stability: the fingerprint must be deterministic across calls.
    $fp1 = Get-WinMintServicedWimFingerprint -BuildConfig $buildConfig -IsoStageKey 'abc123'
    $fp2 = Get-WinMintServicedWimFingerprint -BuildConfig $buildConfig -IsoStageKey 'abc123'
    Assert-True ($fp1 -eq $fp2) 'Fingerprint must be deterministic'

    # Order-independence: appx/tweaks/features sort stable so input order does not matter.
    $shuffled = $buildConfig.PSObject.Copy()
    $shuffled = [pscustomobject]@{
        Architecture       = $buildConfig.Architecture
        EditionMode        = $buildConfig.EditionMode
        Edition            = $buildConfig.Edition
        AppxPackages       = @('Microsoft.GetHelp', 'Microsoft.BingNews')
        RegistryTweaks     = @('developer-qol', 'dark-mode')
        Features           = $buildConfig.Features
        CursorPackKind     = $buildConfig.CursorPackKind
        InputLocale        = $buildConfig.InputLocale
        SystemLocale       = $buildConfig.SystemLocale
        UILanguage         = $buildConfig.UILanguage
        UILanguageFallback = $buildConfig.UILanguageFallback
        UserLocale         = $buildConfig.UserLocale
        SetupUserLocale    = $buildConfig.SetupUserLocale
        Drivers            = $buildConfig.Drivers
    }
    $fpShuffled = Get-WinMintServicedWimFingerprint -BuildConfig $shuffled -IsoStageKey 'abc123'
    Assert-True ($fp1 -eq $fpShuffled) 'Fingerprint must be invariant to appx/tweak ordering'

    # Sensitivity: changing the iso-stage key must change the fingerprint.
    $fpDifferentStage = Get-WinMintServicedWimFingerprint -BuildConfig $buildConfig -IsoStageKey 'xyz999'
    Assert-True ($fp1 -ne $fpDifferentStage) 'Fingerprint must change when IsoStageKey changes'

    # Sensitivity: changing appx must change the fingerprint.
    $modifiedAppx = $buildConfig.PSObject.Copy()
    $modifiedAppx = [pscustomobject]@{
        Architecture       = $buildConfig.Architecture
        EditionMode        = $buildConfig.EditionMode
        Edition            = $buildConfig.Edition
        AppxPackages       = @('Microsoft.BingNews')
        RegistryTweaks     = $buildConfig.RegistryTweaks
        Features           = $buildConfig.Features
        CursorPackKind     = $buildConfig.CursorPackKind
        InputLocale        = $buildConfig.InputLocale
        SystemLocale       = $buildConfig.SystemLocale
        UILanguage         = $buildConfig.UILanguage
        UILanguageFallback = $buildConfig.UILanguageFallback
        UserLocale         = $buildConfig.UserLocale
        SetupUserLocale    = $buildConfig.SetupUserLocale
        Drivers            = $buildConfig.Drivers
    }
    $fpModifiedAppx = Get-WinMintServicedWimFingerprint -BuildConfig $modifiedAppx -IsoStageKey 'abc123'
    Assert-True ($fp1 -ne $fpModifiedAppx) 'Fingerprint must change when AppxPackages changes'

    # Miss → publish → hit round trip.
    Assert-True ($null -eq (Get-WinMintServicedWimCacheHit -Fingerprint $fp1)) 'Empty cache must miss'

    $fakeWim = Join-Path $sandbox 'fake-install.wim'
    [System.IO.File]::WriteAllBytes($fakeWim, [byte[]](1..32))

    Publish-WinMintServicedWimCache -Fingerprint $fp1 -ServicedWimPath $fakeWim
    $hit = Get-WinMintServicedWimCacheHit -Fingerprint $fp1
    Assert-True ($null -ne $hit) 'Published entry must be retrievable'
    Assert-True (Test-Path -LiteralPath $hit) 'Hit must point at an existing file'

    # Different fingerprint still misses (single-slot replaces, so only one entry exists).
    Assert-True ($null -eq (Get-WinMintServicedWimCacheHit -Fingerprint $fpDifferentStage)) 'Different fingerprint must not collide'

    # Single-slot policy: publishing a second entry evicts the first.
    $fakeWim2 = Join-Path $sandbox 'fake-install-2.wim'
    [System.IO.File]::WriteAllBytes($fakeWim2, [byte[]](33..64))
    Publish-WinMintServicedWimCache -Fingerprint $fpDifferentStage -ServicedWimPath $fakeWim2
    Assert-True ($null -eq (Get-WinMintServicedWimCacheHit -Fingerprint $fp1)) 'Single-slot publish must evict prior entry'
    Assert-True ($null -ne (Get-WinMintServicedWimCacheHit -Fingerprint $fpDifferentStage)) 'New entry must be retrievable'

    Write-Host 'Test-ServicedWimCache: PASS'
}
finally {
    if (Test-Path -LiteralPath $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}
