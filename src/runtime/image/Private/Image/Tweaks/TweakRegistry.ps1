#Requires -Version 7.3

# Registry tweak catalog assembly.
#
# Each Tweaks\NN-<id>.ps1 module calls Add-WinMintRegistryTweakModule with the
# tweak definition (id/metadata/set/remove) plus an `appliesTo` curation
# predicate that decides whether the tweak belongs in a given build. The
# registrar assembles two structures:
#
#   $script:RegistryTweaks          - the canonical ordered catalog (definitions
#                                     only, appliesTo stripped). This is the same
#                                     shape consumed today by Invoke-RegistryTweak
#                                     (Tweaks.ps1), Reports.ps1, IntermediatesCache.ps1,
#                                     and the contract tests.
#   $script:RegistryTweakSelectors  - id -> appliesTo scriptblock, used by the
#                                     curation step (Get-WinMintSelectedRegistryTweaks).
#
# Module files are dot-sourced here in numeric-prefix order. This directory glob
# is the one sanctioned exception to WinMint's "explicit dot-source order" rule:
# tweak modules carry no cross-file dependencies, so deterministic filename order
# is sufficient and lets a new tweak be added by dropping in a single file.

$script:RegistryTweaks = [System.Collections.Generic.List[hashtable]]::new()
$script:RegistryTweakSelectors = [ordered]@{}

function Add-WinMintRegistryTweakModule {
    <# <summary>Register one tweak module: appends its definition to the catalog and stores its curation predicate.</summary> #>
    param([Parameter(Mandatory)][hashtable]$Module)

    $id = [string]$Module['id']
    if ([string]::IsNullOrWhiteSpace($id)) {
        throw 'Registry tweak module is missing a non-empty id.'
    }
    if ($script:RegistryTweakSelectors.Contains($id)) {
        throw "Duplicate registry tweak module id '$id'."
    }

    $selector = $Module['appliesTo']
    if ($null -eq $selector) {
        throw "Registry tweak module '$id' must define an 'appliesTo' predicate."
    }
    if ($selector -isnot [scriptblock]) {
        throw "Registry tweak module '$id' appliesTo must be a scriptblock, got [$($selector.GetType().Name)]."
    }

    $definition = @{}
    foreach ($key in $Module.Keys) {
        if ($key -eq 'appliesTo') { continue }
        $definition[$key] = $Module[$key]
    }
    if (-not $definition.ContainsKey('set')) { $definition['set'] = @() }
    if (-not $definition.ContainsKey('remove')) { $definition['remove'] = @() }

    $script:RegistryTweaks.Add($definition)
    $script:RegistryTweakSelectors[$id] = $selector
}

function New-WinMintTweakContext {
    <# <summary>Normalized build facts the curation predicates branch on. Built once per build in New-WinMintBuildConfig.</summary> #>
    param(
        [bool]$PrivacyTelemetry = $true,
        [bool]$PrivacyAdvertisingId = $true,
        [bool]$PrivacyLocation = $true,
        [bool]$KeepGaming = $false,
        [bool]$KeepCopilot = $false,
        [bool]$DesktopUi = $false,
        [string]$DiskMode = 'Manual',
        [bool]$TweakHardwareBypass = $false,
        [bool]$TweakFileExtensions = $true
    )

    [pscustomobject]@{
        PrivacyTelemetry     = $PrivacyTelemetry
        PrivacyAdvertisingId = $PrivacyAdvertisingId
        PrivacyLocation      = $PrivacyLocation
        KeepGaming           = $KeepGaming
        KeepCopilot          = $KeepCopilot
        DesktopUi            = $DesktopUi
        DiskMode             = $DiskMode
        TweakHardwareBypass  = $TweakHardwareBypass
        TweakFileExtensions  = $TweakFileExtensions
    }
}

function Get-WinMintSelectedRegistryTweaks {
    <# <summary>Evaluates each tweak module's appliesTo predicate against the context and returns the ordered list of selected tweak ids.</summary> #>
    param([Parameter(Mandatory)]$Context)

    $selected = [System.Collections.Generic.List[string]]::new()
    foreach ($group in $script:RegistryTweaks) {
        $id = [string]$group['id']
        $selector = $script:RegistryTweakSelectors[$id]
        if ($null -eq $selector) { continue }
        $apply = $false
        try {
            $apply = [bool](& $selector $Context)
        }
        catch {
            throw "Registry tweak selector for '$id' failed: $($_.Exception.Message)"
        }
        if ($apply) { $selected.Add($id) | Out-Null }
    }
    return $selected.ToArray()
}

# Assemble the catalog from the per-tweak modules in this directory.
Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -ErrorAction Stop |
    Where-Object { $_.Name -match '^\d' } |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }
