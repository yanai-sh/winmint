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
        [bool]$UserControlled = $false,
        [string[]]$Changes = @()
    )

    [ordered]@{
        id = $Id
        phase = $Phase
        kind = $Kind
        title = $Title
        userControlled = $UserControlled
        changes = @($Changes | Where-Object { $_ })
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

    return (New-WinMintBuildDeltaRecord `
            -Id "registry:$TweakId" `
            -Phase ([string]$definition.phase) `
            -Kind 'registry-tweak' `
            -Title ([string]$definition.description) `
            -UserControlled ($TweakId -in @('hardware-bypass', 'desktopui-policy', 'location-disabled-policy')) `
            -Changes @($changes.ToArray()))
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
                -Changes @($BuildConfig.AppxPackages | ForEach-Object { "Remove AppX prefix $_" }))) | Out-Null
    }

    $records.Add((New-WinMintBuildDeltaRecord `
            -Id 'ai:policy' `
            -Phase 'offline-image' `
            -Kind 'ai-cleanup' `
            -Title "Apply AI cleanup policy $([string]$BuildConfig.AiRemoval.Policy)" `
            -UserControlled ([bool]$BuildConfig.Keep.Copilot) `
            -Changes @(
                @($BuildConfig.AiRemoval.OptionalFeatures | ForEach-Object { "Remove optional AI feature $_" }) +
                @($BuildConfig.AiRemoval.ServicesToDisable | ForEach-Object { "Disable AI service $_" }) +
                @($BuildConfig.AiRemoval.ScheduledTaskPatternsToDisable | ForEach-Object { "Disable scheduled task pattern $_" })
            ))) | Out-Null

    foreach ($phase in @($effectivePlan.SetupPlan.phases)) {
        $records.Add((New-WinMintBuildDeltaRecord `
                -Id "setup-phase:$([string]$phase.id)" `
                -Phase ([string]$phase.id) `
                -Kind 'setup-phase' `
                -Title "Run setup phase $([string]$phase.id)" `
                -Changes @($phase.responsibilities))) | Out-Null
    }

    foreach ($action in @(Get-WinMintSetupActionCatalog)) {
        $records.Add((New-WinMintBuildDeltaRecord `
                -Id "setup-action:$([string]$action.Id)" `
                -Phase ([string]$action.Phase) `
                -Kind ([string]$action.Kind) `
                -Title ([string]$action.Title) `
                -UserControlled ([bool]$action.UserControlled) `
                -Changes @($action.Changes))) | Out-Null
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
                -UserControlled ([bool]$moduleDefinition.UserControlled) `
                -Changes @($moduleDefinition.Changes))) | Out-Null
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

