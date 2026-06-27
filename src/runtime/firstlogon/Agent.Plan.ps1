#Requires -Version 7.6

function Get-AgentModuleConfig {
    param([Parameter(Mandatory)][string]$Name)
    $agentProfile = (Get-WinMintAgentContext).AgentProfile
    if (-not $agentProfile.modules) { return $null }
    $prop = $agentProfile.modules.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function Resolve-WinMintAgentRoot {
    try {
        $resolved = [string](Get-WinMintAgentContext).AgentRoot
        if (-not [string]::IsNullOrWhiteSpace($resolved)) { return $resolved }
    }
    catch { }
    if ($script:agentRoot) { return [string]$script:agentRoot }
    throw 'WinMint agent root is not initialized.'
}

function Get-WinMintAgentModuleCatalog {
    $catalogPath = Join-Path (Resolve-WinMintAgentRoot) 'agent-module-catalog.json'
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
        throw "Agent module catalog is missing: $catalogPath"
    }

    $entries = @(Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    $requiredKeys = @(
        'Id', 'RelativePath', 'BootstrapFunction', 'RuntimeStepName', 'Enablement',
        'Title', 'Kind', 'FailurePolicy', 'Phase', 'PostStepHook'
    )
    $catalog = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $entries) {
        foreach ($key in $requiredKeys) {
            if (-not $entry.PSObject.Properties[$key]) {
                throw "Agent module catalog entry '$($entry.Id)' is missing required key '$key'."
            }
        }
        $catalog.Add([pscustomobject]@{
                Id = [string]$entry.Id
                RelativePath = [string]$entry.RelativePath
                BootstrapFunction = [string]$entry.BootstrapFunction
                RuntimeStepName = [string]$entry.RuntimeStepName
                Enablement = [string]$entry.Enablement
                Title = [string]$entry.Title
                Kind = [string]$entry.Kind
                Default = [bool]$entry.Default
                Requires = @($entry.Requires | ForEach-Object { [string]$_ })
                SuppressedBy = @($entry.SuppressedBy | ForEach-Object { [string]$_ })
                UserControlled = [bool]$entry.UserControlled
                Changes = @($entry.Changes | ForEach-Object { [string]$_ })
                Artifacts = @($entry.Artifacts | ForEach-Object { [string]$_ })
                Reversible = [bool]$entry.Reversible
                FailurePolicy = [string]$entry.FailurePolicy
                Phase = [string]$entry.Phase
                PostStepHook = [string]$entry.PostStepHook
            }) | Out-Null
    }
    return @($catalog)
}

# NOTE: agent module files are dot-sourced at SCRIPT scope by Start-WinMintAgent.ps1, not
# from a function here - dot-sourcing inside a function would scope the bootstrap functions
# to that function and the step runtime could not see them.

function Test-AgentModuleEnabled {
    param([Parameter(Mandatory)][string]$Name)
    $cfg = Get-AgentModuleConfig -Name $Name
    if (-not $cfg) { return $false }
    $enabledProp = $cfg.PSObject.Properties['enabled']
    if ($enabledProp) { return [bool]$enabledProp.Value }
    foreach ($p in $cfg.PSObject.Properties) {
        if ($p.Value -is [bool] -and $p.Value) { return $true }
    }
    return $false
}

function Get-WinMintAgentModuleRuntimeState {
    param(
        [Parameter(Mandatory)]$ModuleDefinition
    )

    $moduleId = [string]$ModuleDefinition.Id
    $enablement = [string]$ModuleDefinition.Enablement
    switch ($enablement) {
        'always' { return $true }
        'modules.packageManagers.enabled' { return (Test-AgentModuleEnabled -Name 'packageManagers') }
        'modules.wsl.enabled' { return (Test-AgentModuleEnabled -Name 'wsl') }
        'modules.git.enabled' { return (Test-AgentModuleEnabled -Name 'git') }
        'modules.dotfiles.enabled' { return (Test-AgentModuleEnabled -Name 'dotfiles') }
        'modules.raycast.enabled' { return (Test-AgentModuleEnabled -Name 'raycast') }
        'modules.launcherKey.enabled' { return (Test-AgentModuleEnabled -Name 'launcherKey') }
        'modules.phoneLink.enabled' { return (Test-AgentModuleEnabled -Name 'phoneLink') }
        'modules.shell.enabled' { return (Test-AgentModuleEnabled -Name 'shell') }
        'modules.windhawk.enabled' { return (Test-AgentModuleEnabled -Name 'windhawk') }
        'modules.liveInstallAudit.enabled' { return (Test-AgentModuleEnabled -Name 'liveInstallAudit') }
        'browsers.count > 0' { return (@((Get-WinMintAgentContext).AgentProfile.browsers).Count -gt 0) }
        'editors.count > 0' { return (@((Get-WinMintAgentContext).AgentProfile.editors).Count -gt 0) }
        default { throw "Unsupported agent module enablement expression '$enablement' for '$moduleId'." }
    }
}

function New-WinMintAgentRuntimeStepPlan {
    $steps = [System.Collections.Generic.List[object]]::new()
    foreach ($moduleDefinition in @(Get-WinMintAgentModuleCatalog)) {
        $steps.Add([pscustomobject]@{
                Id = "module:$([string]$moduleDefinition.RuntimeStepName)"
                Order = ($steps.Count + 1)
                Phase = [string]$moduleDefinition.Phase
                StepName = [string]$moduleDefinition.RuntimeStepName
                FunctionName = [string]$moduleDefinition.BootstrapFunction
                Enabled = (Get-WinMintAgentModuleRuntimeState -ModuleDefinition $moduleDefinition)
                Enablement = [string]$moduleDefinition.Enablement
                FailurePolicy = [string]$moduleDefinition.FailurePolicy
                PostStepHook = [string]$moduleDefinition.PostStepHook
            }) | Out-Null
    }

    return @($steps)
}

function Set-WinMintAgentNeovimEnvironment {
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    if (@($AgentProfile.editors) -notcontains 'neovim') { return }

    $stateKey = 'tool:neovim'
    try {
        $nvTool = Get-AgentManifestTool -ToolId 'neovim'
        $stateKey = "tool:$([string]$nvTool.id)"
    }
    catch {
        Write-AgentLog "Neovim manifest lookup for EDITOR/VISUAL: $($_.Exception.Message)"
    }

    if ((Test-WinMintAgentStateStepOk -State $State -Key $stateKey) -or
        (Test-WinMintAgentStateStepOk -State $State -Key 'tool:neovim')) {
        [Environment]::SetEnvironmentVariable('EDITOR', 'nvim', 'User')
        [Environment]::SetEnvironmentVariable('VISUAL', 'nvim', 'User')
    }
}

function Invoke-WinMintAgentPostStepHook {
    param(
        [string]$HookName
    )

    if ([string]::IsNullOrWhiteSpace($HookName)) { return }

    $cmd = Get-Command $HookName -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-AgentLog "Post-step hook not found: $HookName"
        Write-AgentEvent -Type 'hook' -Status 'failed' -Message "Post-step hook not found: $HookName"
        return
    }

    try {
        & $HookName -AgentProfile (Get-WinMintAgentContext).AgentProfile -State (Get-WinMintAgentContext).State
    }
    catch {
        Write-AgentLog "Post-step hook '$HookName' failed: $($_.Exception.Message)"
        Write-AgentEvent -Type 'hook' -Status 'failed' -Message "Post-step hook '$HookName' failed: $($_.Exception.Message)" -Data @{
            error = $_.Exception.Message
        }
    }
}

function Invoke-AgentProfileModule {
    param(
        [Parameter(Mandatory)][string]$StepName,
        [Parameter(Mandatory)][string]$FunctionName,
        [bool]$Enabled,
        [string]$PostStepHook = ''
    )

    $ctx = Get-WinMintAgentContext
    $State = $ctx.State
    $agentProfile = $ctx.AgentProfile
    $Force = [bool]$ctx.Force
    $key = "module:$StepName"
    if (-not $Enabled) {
        $State.steps[$key] = @{ status = 'skipped'; updatedAt = (Get-Date -Format o) }
        Save-AgentState -State $State
        Write-AgentEvent -Type 'step' -Status 'skipped' -Step $key -Message "$StepName is not selected."
        return
    }
    if (-not $Force -and $State.steps.ContainsKey($key) -and $State.steps[$key].status -eq 'ok') {
        Write-AgentLog "SKIP $key already ok"
        Write-AgentEvent -Type 'step' -Status 'ok' -Step $key -Message "$StepName already completed."
        Invoke-WinMintAgentPostStepHook -HookName $PostStepHook
        return
    }
    $cmd = Get-Command $FunctionName -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $State.steps[$key] = @{ status = 'failed'; updatedAt = (Get-Date -Format o); error = "$FunctionName not found" }
        Save-AgentState -State $State
        Write-AgentEvent -Type 'step' -Status 'failed' -Step $key -Message "$StepName could not start." -Data @{
            error = "$FunctionName not found"
        }
        Write-AgentLog "FAIL $key :: $FunctionName not found"
        return
    }
    try {
        $attempts = Get-AgentStepAttempts -Step $State.steps[$key]
        $State.steps[$key] = @{
            status = 'running'
            startedAt = (Get-Date -Format o)
            updatedAt = (Get-Date -Format o)
            attempts = ($attempts + 1)
        }
        Save-AgentState -State $State
        Write-AgentEvent -Type 'step' -Status 'running' -Step $key -Message "Starting $StepName." -Data @{
            attempts = ($attempts + 1)
        }
        $result = & $FunctionName -AgentProfile $agentProfile -State $State
        $status = if ($result -and $result.PSObject.Properties['Status']) { [string]$result.Status } else { 'ok' }
        if ($status -eq 'ok' -and $result -and $result.PSObject.Properties['RequiredStateSteps']) {
            Assert-WinMintAgentStateStepsOk -State $State -Keys @($result.RequiredStateSteps) -Context "$StepName bootstrap"
        }
        $State.steps[$key] = @{
            status = $status
            updatedAt = (Get-Date -Format o)
            attempts = ($attempts + 1)
            result = $result
        }
        Write-AgentLog "MODULE $key :: $status"
        Write-AgentEvent -Type 'step' -Status $status -Step $key -Message "$StepName finished: $status." -Data @{
            attempts = ($attempts + 1)
        }
    }
    catch {
        $State.steps[$key] = @{
            status = 'failed'
            updatedAt = (Get-Date -Format o)
            attempts = ($attempts + 1)
            error = $_.Exception.Message
        }
        Write-AgentLog "FAIL $key :: $($_.Exception.Message)"
        Write-AgentEvent -Type 'step' -Status 'failed' -Step $key -Message "$StepName failed." -Data @{
            attempts = ($attempts + 1)
            error = $_.Exception.Message
        }
    }
    Save-AgentState -State $State
    Invoke-WinMintAgentPostStepHook -HookName $PostStepHook
}
