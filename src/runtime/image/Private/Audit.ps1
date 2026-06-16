#Requires -Version 7.6

$script:WinMintBuildDelta = @()

if (-not (Get-Command Get-WinMintSetupActionCatalog -ErrorAction SilentlyContinue)) {
    . (Get-WinMintPath -Name RepoRoot -ChildPath 'src\runtime\setup\Setup.Actions.ps1')
}
if (-not (Get-Command Get-WinMintAgentModuleCatalog -ErrorAction SilentlyContinue)) {
    . (Get-WinMintPath -Name RepoRoot -ChildPath 'src\runtime\firstlogon\Agent.Runtime.ps1')
}

function Clear-WinMintBuildDeltaCatalog {
    [CmdletBinding()]
    param()

    $script:WinMintBuildDelta = @()
}

function Get-WinMintBuildDeltaCatalog {
    [CmdletBinding()]
    param()

    $records = @($script:WinMintBuildDelta | ConvertTo-Json -Depth 16 | ConvertFrom-Json)
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        generatedAt = [DateTimeOffset]::Now.ToString('o')
        records = $records
    }
}

function New-WinMintBuildDeltaRecord {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Title,
        [bool]$Default = $true,
        [string[]]$Requires = @(),
        [string[]]$SuppressedBy = @(),
        [bool]$UserControlled = $false,
        [string[]]$Changes = @(),
        [string[]]$Artifacts = @(),
        [bool]$Reversible = $false,
        [Parameter(Mandatory)][string]$Subsystem,
        [Parameter(Mandatory)][string]$ContributorId
    )

    [ordered]@{
        id = $Id
        phase = $Phase
        kind = $Kind
        title = $Title
        default = $Default
        requires = @($Requires | Where-Object { $_ })
        suppressedBy = @($SuppressedBy | Where-Object { $_ })
        userControlled = $UserControlled
        changes = @($Changes | Where-Object { $_ })
        artifacts = @($Artifacts | Where-Object { $_ })
        reversible = $Reversible
        source = [ordered]@{
            subsystem = $Subsystem
            contributorId = $ContributorId
        }
    }
}

function Get-WinMintRegistryTweakDefinitionById {
    param([Parameter(Mandatory)][string]$Id)

    return @($script:RegistryTweaks | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1)
}

function New-WinMintRegistryTweakBuildDelta {
    param(
        [Parameter(Mandatory)]$BuildConfig,
        [Parameter(Mandatory)][string]$TweakId
    )

    $definition = Get-WinMintRegistryTweakDefinitionById -Id $TweakId
    if (-not $definition) { return $null }

    $changes = [System.Collections.Generic.List[string]]::new()
    foreach ($operation in @($definition.operations.registry)) {
        switch ([string]$operation.kind) {
            'setValue' {
                $changes.Add("Set $($operation.path)\$($operation.name) -> $($operation.value)") | Out-Null
            }
            'removeKey' {
                $changes.Add("Remove key $($operation.path)") | Out-Null
            }
        }
    }

    $suppressedBy = [System.Collections.Generic.List[string]]::new()
    switch ([string]$TweakId) {
        'gamebar-policy' { if ([bool]$BuildConfig.Keep.Gaming) { $suppressedBy.Add('KeepGaming') | Out-Null } }
        'gaming-performance-policy' { if ([bool]$BuildConfig.Keep.Gaming) { $suppressedBy.Add('KeepGaming') | Out-Null } }
        'windows-ai-features-removal' { if ([bool]$BuildConfig.Keep.Copilot) { $suppressedBy.Add('KeepCopilot') | Out-Null } }
        'location-disabled-policy' { if ([bool]$BuildConfig.Privacy.Location) { $suppressedBy.Add('LocationOn') | Out-Null } }
        'hardware-bypass' { $suppressedBy.Add('TweakHardwareBypassOff') | Out-Null }
    }

    return (New-WinMintBuildDeltaRecord `
            -Id "registry:$TweakId" `
            -Phase ([string]$definition.phase) `
            -Kind 'registry-tweak' `
            -Title ([string]$definition.description) `
            -Default ($TweakId -notin @('hardware-bypass', 'dual-boot-windows-policy', 'dual-boot-clock-policy', 'desktopui-policy', 'location-disabled-policy')) `
            -Requires @($definition.dependencies) `
            -SuppressedBy @($suppressedBy.ToArray()) `
            -UserControlled ($TweakId -in @('hardware-bypass', 'desktopui-policy', 'location-disabled-policy')) `
            -Changes @($changes.ToArray()) `
            -Artifacts @('WinMint-TweakAudit.json', 'WinMint-TweakRollback.reg') `
            -Reversible ([bool]$definition.reversible) `
            -Subsystem 'WinMint.Catalog' `
            -ContributorId $TweakId)
}

function New-WinMintBuildDeltaCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$BuildConfig,
        [AllowNull()]$InstallPlan = $null
    )

    $records = [System.Collections.Generic.List[object]]::new()
    $effectivePlan = if ($null -ne $InstallPlan) { $InstallPlan } else { New-WinMintInstallPlanFromBuildConfig -BuildConfig $BuildConfig }

    foreach ($tweakId in @($BuildConfig.RegistryTweaks)) {
        $record = New-WinMintRegistryTweakBuildDelta -BuildConfig $BuildConfig -TweakId ([string]$tweakId)
        if ($record) { $records.Add($record) | Out-Null }
    }

    if (@($BuildConfig.AppxPackages).Count -gt 0) {
        $records.Add((New-WinMintBuildDeltaRecord `
                -Id 'appx:baseline-removal' `
                -Phase 'offline-image' `
                -Kind 'appx-removal' `
                -Title 'Remove selected Microsoft AppX payloads from the offline image' `
                -Default $true `
                -Changes @($BuildConfig.AppxPackages | ForEach-Object { "Remove AppX prefix $_" }) `
                -Artifacts @('WinMint-BuildManifest.json') `
                -Reversible $false `
                -Subsystem 'WinMint.Engine' `
                -ContributorId 'appx-removal')) | Out-Null
    }

    $records.Add((New-WinMintBuildDeltaRecord `
            -Id 'ai:policy' `
            -Phase 'offline-image' `
            -Kind 'ai-cleanup' `
            -Title "Apply AI cleanup policy $([string]$BuildConfig.AiRemoval.Policy)" `
            -Default $true `
            -SuppressedBy $(if ([bool]$BuildConfig.Keep.Copilot) { @('KeepCopilot') } else { @() }) `
            -UserControlled ([bool]$BuildConfig.Keep.Copilot) `
            -Changes @(
                @($BuildConfig.AiRemoval.OptionalFeatures | ForEach-Object { "Remove optional AI feature $_" }) +
                @($BuildConfig.AiRemoval.ServicesToDisable | ForEach-Object { "Disable AI service $_" }) +
                @($BuildConfig.AiRemoval.ScheduledTaskPatternsToDisable | ForEach-Object { "Disable scheduled task pattern $_" })
            ) `
            -Artifacts @('WinMint-BuildManifest.json', 'recovery/WinMint-Recovery.json') `
            -Reversible $true `
            -Subsystem 'WinMint.Catalog' `
            -ContributorId 'ai-removal')) | Out-Null

    foreach ($phase in @($effectivePlan.SetupPlan.phases)) {
        $records.Add((New-WinMintBuildDeltaRecord `
                -Id "setup-phase:$([string]$phase.id)" `
                -Phase ([string]$phase.id) `
                -Kind 'setup-phase' `
                -Title "Run setup phase $([string]$phase.id)" `
                -Default $true `
                -Changes @($phase.responsibilities) `
                -Artifacts @('WinMintSetupPlan.json') `
                -Reversible $false `
                -Subsystem 'WinMint.Setup' `
                -ContributorId ([string]$phase.id))) | Out-Null
    }

    foreach ($action in @(Get-WinMintSetupActionCatalog)) {
        $records.Add((New-WinMintBuildDeltaRecord `
                -Id "setup-action:$([string]$action.Id)" `
                -Phase ([string]$action.Phase) `
                -Kind ([string]$action.Kind) `
                -Title ([string]$action.Title) `
                -Default ([bool]$action.Default) `
                -Requires @($action.Requires) `
                -SuppressedBy @($action.SuppressedBy) `
                -UserControlled ([bool]$action.UserControlled) `
                -Changes @($action.Changes) `
                -Artifacts @($action.Artifacts) `
                -Reversible ([bool]$action.Reversible) `
                -Subsystem 'WinMint.Setup' `
                -ContributorId ([string]$action.Id))) | Out-Null
    }

    $selectedModuleIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $selectedModuleIds.Add('profiles') | Out-Null
    foreach ($moduleName in @($effectivePlan.SetupPlan.firstLogon.modules)) {
        $selectedModuleIds.Add([string]$moduleName) | Out-Null
    }
    foreach ($moduleDefinition in @(Get-WinMintAgentModuleCatalog)) {
        $moduleId = [string]$moduleDefinition.Id
        if (-not $selectedModuleIds.Contains($moduleId)) { continue }

        $records.Add((New-WinMintBuildDeltaRecord `
                -Id "firstlogon:$moduleId" `
                -Phase 'first-logon' `
                -Kind ([string]$moduleDefinition.Kind) `
                -Title ([string]$moduleDefinition.Title) `
                -Default ([bool]$moduleDefinition.Default) `
                -Requires @($moduleDefinition.Requires) `
                -SuppressedBy @($moduleDefinition.SuppressedBy) `
                -UserControlled ([bool]$moduleDefinition.UserControlled) `
                -Changes @($moduleDefinition.Changes) `
                -Artifacts @($moduleDefinition.Artifacts) `
                -Reversible ([bool]$moduleDefinition.Reversible) `
                -Subsystem 'WinMint.FirstLogon' `
                -ContributorId $moduleId)) | Out-Null
    }

    $script:WinMintBuildDelta = $records.ToArray()
    return (Get-WinMintBuildDeltaCatalog)
}

function Save-WinMintBuildDeltaCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OutputDir
    )

    $path = Join-Path $OutputDir 'WinMint-BuildDelta.json'
    (Get-WinMintBuildDeltaCatalog) | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

