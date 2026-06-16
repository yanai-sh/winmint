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

function Get-WinMintRegistryTweakValue {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        [object]$Default = $null
    )

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Split-WinMintRegistryTweakPath {
    param([Parameter(Mandatory)][string]$Path)

    $trimmed = $Path.Trim('\')
    $parts = @($trimmed -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts.Count -lt 2) {
        throw "Registry path '$Path' must include a loaded hive alias and at least one subkey."
    }

    [pscustomobject]@{
        HiveAlias = [string]$parts[0]
        SubPath = ($parts | Select-Object -Skip 1) -join '\'
        Depth = $parts.Count - 1
        Normalized = ($parts -join '\')
    }
}

function Assert-WinMintRegistryTweakPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$TweakId,
        [Parameter(Mandatory)][string]$OperationKind
    )

    $parsed = Split-WinMintRegistryTweakPath -Path $Path
    $allowedHives = @('zSYSTEM', 'zSOFTWARE', 'zNTUSER', 'zDEFAULT')
    if ($allowedHives -notcontains $parsed.HiveAlias) {
        throw "Registry tweak '$TweakId' uses unsupported hive alias '$($parsed.HiveAlias)' in $OperationKind path '$Path'."
    }

    if ($parsed.Normalized -match '(^|\\)\.\.?(\\|$)') {
        throw "Registry tweak '$TweakId' uses unsafe relative path segment in $OperationKind path '$Path'."
    }

    return $parsed
}

function Assert-WinMintRegistryTweakSetOperation {
    param(
        [Parameter(Mandatory)]$Entry,
        [Parameter(Mandatory)][string]$TweakId
    )

    $path = [string](Get-WinMintRegistryTweakValue -Object $Entry -Name 'path' -Default '')
    $name = [string](Get-WinMintRegistryTweakValue -Object $Entry -Name 'name' -Default '')
    $type = [string](Get-WinMintRegistryTweakValue -Object $Entry -Name 'type' -Default '')
    $value = Get-WinMintRegistryTweakValue -Object $Entry -Name 'value' -Default $null
    if ([string]::IsNullOrWhiteSpace($path)) { throw "Registry tweak '$TweakId' has a set operation without path." }
    if ([string]::IsNullOrWhiteSpace($type)) { throw "Registry tweak '$TweakId' has a set operation for '$path\\$name' without type." }
    $null = Assert-WinMintRegistryTweakPath -Path $path -TweakId $TweakId -OperationKind 'set'

    $allowedTypes = @('REG_SZ', 'REG_EXPAND_SZ', 'REG_DWORD', 'REG_QWORD', 'REG_BINARY', 'REG_MULTI_SZ')
    if ($allowedTypes -notcontains $type) {
        throw "Registry tweak '$TweakId' has unsupported registry type '$type' for '$path\\$name'."
    }

    if ($null -eq $value) {
        throw "Registry tweak '$TweakId' set operation '$path\\$name' must use remove/undo for deletion; value cannot be null."
    }

    if ($type -in @('REG_DWORD', 'REG_QWORD')) {
        $text = [string]$value
        $parseStyle = [System.Globalization.NumberStyles]::Integer
        if ($text -match '^0x[0-9a-fA-F]+$') {
            $text = $text.Substring(2)
            $parseStyle = [System.Globalization.NumberStyles]::HexNumber
        }
        $parsed = 0L
        if (-not [long]::TryParse($text, $parseStyle, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
            throw "Registry tweak '$TweakId' value '$value' for '$path\\$name' is not valid $type data."
        }
    }
}

function Assert-WinMintRegistryTweakRemoveOperation {
    param(
        [Parameter(Mandatory)]$Entry,
        [Parameter(Mandatory)][string]$TweakId
    )

    $path = [string](Get-WinMintRegistryTweakValue -Object $Entry -Name 'path' -Default '')
    if ([string]::IsNullOrWhiteSpace($path)) { throw "Registry tweak '$TweakId' has a remove operation without path." }
    $parsed = Assert-WinMintRegistryTweakPath -Path $path -TweakId $TweakId -OperationKind 'remove'
    if ($parsed.Depth -lt 3) {
        throw "Registry tweak '$TweakId' remove path '$path' is too shallow; destructive deletes must target a narrow subkey."
    }

    $protectedRoots = @(
        'zSYSTEM\ControlSet001',
        'zSYSTEM\ControlSet001\Control',
        'zSYSTEM\ControlSet001\Services',
        'zSOFTWARE\Microsoft',
        'zSOFTWARE\Policies',
        'zSOFTWARE\Classes',
        'zNTUSER\Software',
        'zDEFAULT\SOFTWARE'
    )
    if ($protectedRoots -contains $parsed.Normalized) {
        throw "Registry tweak '$TweakId' remove path '$path' targets a protected root."
    }
}

function ConvertTo-WinMintRegistryOperation {
    param(
        [Parameter(Mandatory)]$Entry,
        [Parameter(Mandatory)][string]$TweakId,
        [Parameter(Mandatory)][ValidateSet('setValue', 'removeKey')][string]$Kind
    )

    $path = [string](Get-WinMintRegistryTweakValue -Object $Entry -Name 'path' -Default '')
    $parsed = Split-WinMintRegistryTweakPath -Path $path
    $operation = [ordered]@{
        kind = $Kind
        phase = 'offline-image'
        hive = $parsed.HiveAlias
        subPath = $parsed.SubPath
        path = $parsed.Normalized
    }
    if ($Kind -eq 'setValue') {
        $operation.name = [string](Get-WinMintRegistryTweakValue -Object $Entry -Name 'name' -Default '')
        $operation.type = [string](Get-WinMintRegistryTweakValue -Object $Entry -Name 'type' -Default '')
        $operation.value = Get-WinMintRegistryTweakValue -Object $Entry -Name 'value' -Default ''
        $operation.undo = Get-WinMintRegistryTweakValue -Object $Entry -Name 'undo' -Default $null
    }
    else {
        $operation.restore = Get-WinMintRegistryTweakValue -Object $Entry -Name 'restore' -Default $null
    }
    return $operation
}

function Assert-WinMintRegistryTweakDefinition {
    param([Parameter(Mandatory)][hashtable]$Definition)

    $id = [string](Get-WinMintRegistryTweakValue -Object $Definition -Name 'id' -Default '')
    foreach ($entry in @(Get-WinMintRegistryTweakValue -Object $Definition -Name 'set' -Default @())) {
        Assert-WinMintRegistryTweakSetOperation -Entry $entry -TweakId $id
    }
    foreach ($entry in @(Get-WinMintRegistryTweakValue -Object $Definition -Name 'remove' -Default @())) {
        Assert-WinMintRegistryTweakRemoveOperation -Entry $entry -TweakId $id
    }
}

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
    if (-not $definition.ContainsKey('dependencies')) { $definition['dependencies'] = @() }
    if (-not $definition.ContainsKey('guards')) { $definition['guards'] = @() }

    Assert-WinMintRegistryTweakDefinition -Definition $definition
    $registryOperations = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($definition['set'])) {
        $registryOperations.Add((ConvertTo-WinMintRegistryOperation -Entry $entry -TweakId $id -Kind 'setValue')) | Out-Null
    }
    foreach ($entry in @($definition['remove'])) {
        $registryOperations.Add((ConvertTo-WinMintRegistryOperation -Entry $entry -TweakId $id -Kind 'removeKey')) | Out-Null
    }
    $definition['operations'] = [ordered]@{ registry = $registryOperations.ToArray() }

    $script:RegistryTweaks.Add($definition)
    $script:RegistryTweakSelectors[$id] = $selector
}

function Assert-WinMintRegistryTweakCatalog {
    <# <summary>Static safety validation for the loaded tweak catalog.</summary> #>
    $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($group in @($script:RegistryTweaks)) {
        $id = [string](Get-WinMintRegistryTweakValue -Object $group -Name 'id' -Default '')
        if (-not $ids.Add($id)) {
            throw "Duplicate registry tweak id '$id'."
        }
        Assert-WinMintRegistryTweakDefinition -Definition $group
        $operations = Get-WinMintRegistryTweakValue -Object $group -Name 'operations' -Default $null
        if ($null -eq $operations -or @($operations.registry).Count -ne (@($group.set).Count + @($group.remove).Count)) {
            throw "Registry tweak '$id' operation DOM is missing or out of sync."
        }
    }
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

Assert-WinMintRegistryTweakCatalog
