#Requires -Version 7.3
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$InteractiveFirstLogon,
    [switch]$EmitProgressJson
)

$ErrorActionPreference = 'Continue'
$agentRoot = Split-Path -Parent $PSCommandPath
$stateDir = Join-Path $env:LOCALAPPDATA 'WinMint'
$logDir = Join-Path $stateDir 'Logs'
$statePath = Join-Path $stateDir 'state.json'
$eventLogPath = Join-Path $logDir 'WinMintAgent-events.jsonl'
$manifestPath = Join-Path $agentRoot 'packages.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    $repoManifest = Join-Path (Split-Path -Parent (Split-Path -Parent $agentRoot)) 'config\packages.json'
    if (Test-Path -LiteralPath $repoManifest) { $manifestPath = $repoManifest }
}
$profilePath = Join-Path $agentRoot 'BuildProfile.json'
$script:AgentModuleRoot = Join-Path $agentRoot 'Modules'
$null = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue
$commandLogDir = Join-Path $logDir 'Commands'
$null = New-Item -ItemType Directory -Path $commandLogDir -Force -ErrorAction SilentlyContinue
$script:AgentConsoleReady = $false
$script:AgentCommandCounter = 0

. (Join-Path $agentRoot 'Agent.Console.ps1')
. (Join-Path $agentRoot 'Agent.Runtime.ps1')

Write-AgentLog 'WinMintAgent start'
Write-AgentEvent -Type 'run' -Status 'starting' -Message 'WinMintAgent start'
Initialize-AgentConsole
Show-AgentConsoleHeader
Update-AgentProcessPath
# Dot-source agent modules at SCRIPT scope so their Invoke-WinMintAgent* functions are
# visible to the step runner below. Dot-sourcing inside a helper function (or inside a
# ForEach-Object block) defines the functions in a child scope that is discarded on
# return, so every enabled module failed with "<function> not found".
if (Test-Path -LiteralPath $script:AgentModuleRoot) {
    foreach ($agentModuleFile in (Get-ChildItem -LiteralPath $script:AgentModuleRoot -Filter '*.ps1' -File | Sort-Object -Property Name)) {
        . $agentModuleFile.FullName
    }
}
$state = Read-AgentJson -Path $statePath -Fallback ([pscustomobject]@{ version = 1; steps = @{} })
# Read-AgentJson returns a PSCustomObject whenever state.json already exists (a prior
# failed run, or a reboot mid-run). Every agent module function takes [hashtable]$State,
# so normalize the whole object - and its steps map - to hashtables before the step
# runner passes $state into them; otherwise parameter coercion throws "Cannot convert
# ... PSCustomObject ... to type System.Collections.Hashtable" and the step fails before
# it runs. (This was masked until the module-loader scope fix let modules load at all.)
if ($state -isnot [hashtable]) {
    $stateCopy = @{}
    foreach ($p in $state.PSObject.Properties) { $stateCopy[$p.Name] = $p.Value }
    $state = $stateCopy
}
if (-not $state.ContainsKey('steps') -or $state['steps'] -isnot [hashtable]) {
    $copy = @{}
    $existingSteps = if ($state.ContainsKey('steps')) { $state['steps'] } else { $null }
    if ($null -ne $existingSteps) {
        foreach ($p in $existingSteps.PSObject.Properties) { $copy[$p.Name] = $p.Value }
    }
    $state['steps'] = $copy
}
$manifest = Read-AgentJson -Path $manifestPath -Fallback $null
$agentProfile = Read-AgentJson -Path $profilePath -Fallback ([pscustomobject]@{ editors = @(); browsers = @() })
$script:AgentTargetArchitecture = if ($agentProfile.PSObject.Properties['targetArchitecture'] -and -not [string]::IsNullOrWhiteSpace([string]$agentProfile.targetArchitecture)) {
    [string]$agentProfile.targetArchitecture
} else {
    Get-AgentProcessorArchitecture
}
Set-AgentStateValue -State $state -Name 'run' -Value @{
    status = 'running'
    startedAt = (Get-Date -Format o)
    hostArchitecture = Get-AgentProcessorArchitecture
    targetArchitecture = $script:AgentTargetArchitecture
    interactiveFirstLogon = [bool]$InteractiveFirstLogon
    progressEventLog = $eventLogPath
}
Save-AgentState -State $state
Write-AgentEvent -Type 'run' -Status 'running' -Message 'FirstLogon agent is running.'
Show-AgentPlan

if (-not $manifest) {
    Write-AgentLog "Manifest missing: $manifestPath"
    $state.steps['manifest'] = @{ status = 'failed'; updatedAt = (Get-Date -Format o); error = 'packages.json missing' }
    Set-AgentStateValue -State $state -Name 'run' -Value @{
        status = 'failed'
        completedAt = (Get-Date -Format o)
        exitCode = 1
        reason = 'packages.json missing'
    }
    Save-AgentState -State $state
    Write-AgentEvent -Type 'run' -Status 'failed' -Step 'manifest' -Message 'Package manifest missing.'
    Write-AgentConsoleLine -Level Error -Message "Package manifest missing: $manifestPath"
    Wait-AgentConsoleBeforeClose -Failed $true
    exit 1
}

Invoke-AgentProfileModule -StepName 'profiles' -FunctionName 'Invoke-WinMintAgentProfileBootstrap' -Enabled $true
Invoke-AgentProfileModule -StepName 'package-managers' -FunctionName 'Invoke-WinMintAgentPackageManagerBootstrap' -Enabled (Test-AgentModuleEnabled -Name 'packageManagers')
Invoke-AgentProfileModule -StepName 'wsl' -FunctionName 'Invoke-WinMintAgentWslBootstrap' -Enabled (Test-AgentModuleEnabled -Name 'wsl')
Invoke-AgentProfileModule -StepName 'git' -FunctionName 'Invoke-WinMintAgentGitBootstrap' -Enabled (Test-AgentModuleEnabled -Name 'git')
Invoke-AgentProfileModule -StepName 'dotfiles' -FunctionName 'Invoke-WinMintAgentDotfileBootstrap' -Enabled (Test-AgentModuleEnabled -Name 'dotfiles')
Invoke-AgentProfileModule -StepName 'flow-everything' -FunctionName 'Invoke-WinMintAgentFlowEverythingBootstrap' -Enabled (Test-AgentModuleEnabled -Name 'flowEverything')
Invoke-AgentProfileModule -StepName 'raycast' -FunctionName 'Invoke-WinMintAgentRaycastBootstrap' -Enabled (Test-AgentModuleEnabled -Name 'raycast')
Invoke-AgentProfileModule -StepName 'phone-link' -FunctionName 'Invoke-WinMintAgentPhoneLinkBootstrap' -Enabled (Test-AgentModuleEnabled -Name 'phoneLink')
Invoke-AgentProfileModule -StepName 'tiling-desktop' -FunctionName 'Invoke-WinMintAgentTilingDesktopBootstrap' -Enabled (Test-AgentModuleEnabled -Name 'shell')
Invoke-AgentProfileModule -StepName 'windhawk' -FunctionName 'Invoke-WinMintAgentWindhawkBootstrap' -Enabled (Test-AgentModuleEnabled -Name 'windhawk')
Invoke-AgentProfileModule -StepName 'browsers' -FunctionName 'Invoke-WinMintAgentBrowsersBootstrap' -Enabled (@($agentProfile.browsers).Count -gt 0)

Invoke-AgentProfileModule -StepName 'editors' -FunctionName 'Invoke-WinMintAgentEditorBootstrap' -Enabled (@($agentProfile.editors).Count -gt 0)

if (@($agentProfile.editors) -contains 'neovim') {
    $neovimStepOk = $false
    try {
        $nvTool = Get-AgentManifestTool -ToolId 'neovim'
        $nvKey = "tool:$([string]$nvTool.id)"
        if ($state.steps.ContainsKey($nvKey) -and [string]$state.steps[$nvKey].status -eq 'ok') {
            $neovimStepOk = $true
        }
    }
    catch {
        Write-AgentLog "Neovim manifest lookup for EDITOR/VISUAL: $($_.Exception.Message)"
    }
    if (-not $neovimStepOk -and $state.steps.ContainsKey('tool:neovim') -and
        [string]$state.steps['tool:neovim'].status -eq 'ok') {
        $neovimStepOk = $true
    }
    if ($neovimStepOk) {
        [Environment]::SetEnvironmentVariable('EDITOR', 'nvim', 'User')
        [Environment]::SetEnvironmentVariable('VISUAL', 'nvim', 'User')
    }
}

Invoke-AgentProfileModule -StepName 'liveInstallAudit' -FunctionName 'Invoke-WinMintAgentLiveInstallAuditBootstrap' -Enabled (Test-AgentModuleEnabled -Name 'liveInstallAudit')

# Live-user modules are best-effort. A failed app/tool install must not keep
# autologon credentials resident or block final desktop personalization; the
# summary and state file carry the retry/manual-repair details.
$blockingSteps = @('module:profiles')
$allFailed = @($state.steps.GetEnumerator() | Where-Object { $_.Value.status -eq 'failed' })
$advisoryFailed = @($allFailed | Where-Object { [string]$_.Key -notin $blockingSteps })
$failed = @($allFailed | Where-Object { [string]$_.Key -in $blockingSteps })
foreach ($a in $advisoryFailed) {
    Write-AgentLog "Live step '$([string]$a.Key)' failed (non-blocking); continuing so setup can finish."
}
if ($failed.Count -gt 0) {
    $rebootPending = Test-AgentRebootPending
    Set-AgentStateValue -State $state -Name 'failedAt' -Value (Get-Date -Format o)
    Set-AgentStateValue -State $state -Name 'run' -Value @{
        status = 'failed'
        completedAt = (Get-Date -Format o)
        exitCode = 1
        failedSteps = @($failed | ForEach-Object { [string]$_.Key })
        rebootPending = $rebootPending
    }
    Save-AgentState -State $state
    Write-AgentEvent -Type 'run' -Status 'failed' -Message "FirstLogon failed: $($failed.Count) failed step(s)." -Data @{
        failedSteps = @($failed | ForEach-Object { [string]$_.Key })
        rebootPending = $rebootPending
    }
    if ($rebootPending) { Write-AgentLog 'Windows reports a pending reboot after the failed FirstLogon run.' }
    Write-AgentLog "WinMintAgent failed: $($failed.Count) failed step(s)."
    Show-AgentFinalSummary -State $state
    Wait-AgentConsoleBeforeClose -Failed $true
    exit 1
}
else {
    $rebootPending = Test-AgentRebootPending
    Set-AgentStateValue -State $state -Name 'completedAt' -Value (Get-Date -Format o)
    $warningSteps = @($advisoryFailed | ForEach-Object { [string]$_.Key })
    Set-AgentStateValue -State $state -Name 'run' -Value @{
        status = 'ok'
        completedAt = (Get-Date -Format o)
        exitCode = 0
        rebootPending = $rebootPending
        warningSteps = $warningSteps
    }
    Save-AgentState -State $state
    $message = if ($warningSteps.Count -gt 0) { 'FirstLogon agent completed with warnings.' } else { 'FirstLogon agent completed.' }
    Write-AgentEvent -Type 'run' -Status 'ok' -Message $message -Data @{
        rebootPending = $rebootPending
        warningSteps = $warningSteps
    }
    if ($rebootPending) { Write-AgentLog 'Windows reports a pending reboot after the successful FirstLogon run.' }
    if ($warningSteps.Count -gt 0) { Write-AgentLog "WinMintAgent completed with warning step(s): $($warningSteps -join ', ')" }
    else { Write-AgentLog 'WinMintAgent end' }
    Show-AgentFinalSummary -State $state
    Wait-AgentConsoleBeforeClose -Failed $false -Warnings:($warningSteps.Count -gt 0)
    exit 0
}
