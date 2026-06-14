#Requires -Version 7.3

function Get-WinMintAiRemovalCatalog {
    $path = Get-WinMintPath -Name ConfigRoot -ChildPath 'ai-removal.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "AI removal catalog missing: $path"
    }
    Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Resolve-WinMintAiRemovalPolicy {
    param(
        [object]$Removals
    )

    $policy = [string](Get-WinMintProfileSetting $Removals 'aiPolicy' '')
    if ([string]::IsNullOrWhiteSpace($policy)) {
        # Subtractive default: full serviceable AI removal on every build.
        $policy = 'ServiceableFull'
    }
    if ($policy -notin @('Core', 'ServiceableFull', 'AggressiveExperimental')) {
        throw "Unsupported AI removal policy '$policy'."
    }
    if ($policy -eq 'AggressiveExperimental' -and [string]$env:WINMINT_ENABLE_EXPERIMENTAL_AI_REMOVAL -ne '1') {
        throw 'AggressiveExperimental AI removal is internal-only. Set WINMINT_ENABLE_EXPERIMENTAL_AI_REMOVAL=1 to enable it for development.'
    }
    return $policy
}

function New-WinMintAiRemovalConfig {
    param(
        [object]$Removals,
        [bool]$KeepCopilot = $false
    )

    $catalog = Get-WinMintAiRemovalCatalog
    $policy = Resolve-WinMintAiRemovalPolicy -Removals $Removals
    $serviceablePrefixes = @()
    if ($policy -in @('ServiceableFull', 'AggressiveExperimental')) {
        $serviceablePrefixes = @($catalog.serviceableAppxPrefixes | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
    }

    # -KeepCopilot keeps ALL Copilot+ AI features (apps, services, AI tasks).
    # Recall is the security exception: its optional feature and the 'Recall'
    # scheduled task are ALWAYS removed regardless of -KeepCopilot.
    if ($KeepCopilot) {
        $serviceablePrefixes = @()
        $servicesToDisable = @()
        $scheduledTaskPatternsToDisable = @('Recall')
    }
    else {
        $servicesToDisable = @($catalog.servicesToDisable | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
        $scheduledTaskPatternsToDisable = @($catalog.scheduledTaskPatternsToDisable | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
    }

    [pscustomobject]@{
        Policy = $policy
        CatalogVersion = [int]$catalog.catalogVersion
        KeepCopilot = $KeepCopilot
        AppxPrefixes = $serviceablePrefixes
        OptionalFeatures = @($catalog.optionalFeatures | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
        ServicesToDisable = @($servicesToDisable)
        ScheduledTaskPatternsToDisable = @($scheduledTaskPatternsToDisable)
        AggressiveExperimental = ($policy -eq 'AggressiveExperimental')
        AggressiveExperimentalPatterns = if ($policy -eq 'AggressiveExperimental') {
            @($catalog.aggressiveExperimentalPatterns | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
        } else {
            @()
        }
    }
}

function Test-WinMintNameMatchesAnyPrefix {
    param(
        [string]$Name,
        [string[]]$Prefixes = @()
    )

    foreach ($prefix in @($Prefixes)) {
        if ([string]::IsNullOrWhiteSpace($prefix)) { continue }
        if ($Name -like "*$prefix*") { return $true }
    }
    return $false
}

function Invoke-WinMintOfflineAiFeatureRemoval {
    param(
        [ValidateNotNullOrEmpty()][string]$MountDir,
        [Parameter(Mandatory)]$AiRemoval
    )

    if ([string]$AiRemoval.Policy -eq 'Core') { return }
    $removed = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[object]]::new()

    Write-SectionHeader 'Image: Windows AI optional features'
    Invoke-Action 'Removing serviceable Windows AI optional features' {
        foreach ($feature in @($AiRemoval.OptionalFeatures)) {
            if ([string]::IsNullOrWhiteSpace([string]$feature)) { continue }
            try {
                Invoke-DismExe -Arguments @('/English', "/Image:$MountDir", '/Disable-Feature', "/FeatureName:$feature", '/Remove') | Out-Null
                $removed.Add([string]$feature) | Out-Null
                LogOK "Removed optional feature payload: $feature"
            }
            catch {
                $failed.Add([ordered]@{
                    action = 'RemoveOptionalFeature'
                    target = [string]$feature
                    error = $_.Exception.Message
                }) | Out-Null
                LogWarn "AI optional feature not present or could not be removed: $feature"
            }
        }
    }

    Add-WinMintManifestAiOptionalFeatureRemovalFacts -RemovedFeatures $removed.ToArray() -Failed $failed.ToArray()
}
