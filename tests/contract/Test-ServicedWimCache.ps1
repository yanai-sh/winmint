#Requires -Version 7.6
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Minimal stubs for log helpers the cache module uses.
function Log { param([string]$m) }
function LogVerbose { param([string]$m) }

. (Join-Path $root 'src\runtime\image\Private\IntermediatesCache.ps1')

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
        AppxCatalogVersion = 1
        AppxPackages       = @('Microsoft.BingNews', 'Microsoft.GetHelp')
        AiRemoval          = [pscustomobject]@{
            Policy           = 'Core'
            CatalogVersion   = 1
            AppxPrefixes     = @()
            OptionalFeatures = @()
        }
        RegistryTweaks     = @('dark-mode', 'explorer-qol')
        Features           = @('OpenSSH.Client', 'Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')
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
        AppxCatalogVersion = $buildConfig.AppxCatalogVersion
        AppxPackages       = @('Microsoft.GetHelp', 'Microsoft.BingNews')
        AiRemoval          = $buildConfig.AiRemoval
        RegistryTweaks     = @('explorer-qol', 'dark-mode')
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
        AppxCatalogVersion = $buildConfig.AppxCatalogVersion
        AppxPackages       = @('Microsoft.BingNews')
        AiRemoval          = $buildConfig.AiRemoval
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

    $modifiedCatalog = $buildConfig.PSObject.Copy()
    $modifiedCatalog.AppxCatalogVersion = 2
    $fpModifiedCatalog = Get-WinMintServicedWimFingerprint -BuildConfig $modifiedCatalog -IsoStageKey 'abc123'
    Assert-True ($fp1 -ne $fpModifiedCatalog) 'Fingerprint must change when AppxCatalogVersion changes'

    $modifiedAiCatalog = $buildConfig.PSObject.Copy()
    $modifiedAiCatalog.AiRemoval = [pscustomobject]@{
        Policy           = 'ServiceableFull'
        CatalogVersion   = 2
        AppxPrefixes     = @('Microsoft.Windows.Copilot')
        OptionalFeatures = @('Recall')
    }
    $fpModifiedAiCatalog = Get-WinMintServicedWimFingerprint -BuildConfig $modifiedAiCatalog -IsoStageKey 'abc123'
    Assert-True ($fp1 -ne $fpModifiedAiCatalog) 'Fingerprint must change when AI removal catalog inputs change'

    $driverDir = Join-Path $sandbox 'drivers'
    $null = New-Item -ItemType Directory -Path (Join-Path $driverDir 'nested') -Force
    Set-Content -LiteralPath (Join-Path $driverDir 'device.inf') -Value 'version=1' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $driverDir 'nested\device.sys') -Value 'payload=1' -Encoding ASCII
    $driverConfig = $buildConfig.PSObject.Copy()
    $driverConfig.Drivers = [pscustomobject]@{ Source = 'Custom'; Path = $driverDir }
    $fpDriver1 = Get-WinMintServicedWimFingerprint -BuildConfig $driverConfig -IsoStageKey 'abc123'
    Set-Content -LiteralPath (Join-Path $driverDir 'nested\device.sys') -Value 'payload=2' -Encoding ASCII
    $fpDriver2 = Get-WinMintServicedWimFingerprint -BuildConfig $driverConfig -IsoStageKey 'abc123'
    Assert-True ($fpDriver1 -ne $fpDriver2) 'Fingerprint must change when nested driver payload content changes'

    # Miss → publish → hit round trip.
    Assert-True ($null -eq (Get-WinMintServicedWimCacheHit -Fingerprint $fp1)) 'Empty cache must miss'

    $fakeWim = Join-Path $sandbox 'fake-install.wim'
    [System.IO.File]::WriteAllBytes($fakeWim, [byte[]](1..32))

    $expectedMeta = @([pscustomobject]@{ ImageIndex = 1; Name = 'Windows 11 Home'; Build = 26100; Edition = 'Core'; Languages = @('en-US') })
    Publish-WinMintServicedWimCache -Fingerprint $fp1 -ServicedWimPath $fakeWim -ExpectedMetadata $expectedMeta
    $hit = Get-WinMintServicedWimCacheHit -Fingerprint $fp1 -ExpectedMetadata $expectedMeta
    Assert-True ($null -ne $hit) 'Published entry must be retrievable'
    Assert-True (Test-Path -LiteralPath $hit) 'Hit must point at an existing file'
    $wrongMeta = @([pscustomobject]@{ ImageIndex = 1; Name = 'Windows 11 Pro'; Build = 26100; Edition = 'Professional'; Languages = @('en-US') })
    Assert-True ($null -eq (Get-WinMintServicedWimCacheHit -Fingerprint $fp1 -ExpectedMetadata $wrongMeta)) 'Cache hit must reject mismatched expected source metadata'

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

