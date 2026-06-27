#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$InteractiveFirstLogon,
    [switch]$EmitProgressJson
)

$ErrorActionPreference = 'Continue'

# WinMint setup work needs PowerShell 7+. In the installed image FirstLogon already
# relaunches the whole chain under the bundled pwsh 7 before reaching here, so this is
# normally a no-op; it only matters when the agent is started directly (e.g. dev testing)
# under Windows PowerShell 5.1. Relaunch in place and exit with the child's code.
# ponytail: self-contained on purpose - the staged guest agent has no repo tree to import
# WinMint.Bootstrap from. No winget-install fallback like the host module: the image always
# bundles pwsh 7, so a missing pwsh 7 here is a hard error, not something to repair at logon.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh7 = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if (-not (Test-Path -LiteralPath $pwsh7 -PathType Leaf)) {
        Write-Error "PowerShell 7 is required for WinMintAgent but was not found: $pwsh7"
        exit 1
    }
    $relaunchArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($Force) { $relaunchArgs += '-Force' }
    if ($InteractiveFirstLogon) { $relaunchArgs += '-InteractiveFirstLogon' }
    if ($EmitProgressJson) { $relaunchArgs += '-EmitProgressJson' }
    & $pwsh7 @relaunchArgs
    exit $LASTEXITCODE
}

$agentRoot = Split-Path -Parent $PSCommandPath
foreach ($candidate in @(
        Join-Path $agentRoot 'WinMint.Runtime.Common.ps1'
        Join-Path (Split-Path -Parent $agentRoot) 'WinMint.Runtime.Common.ps1'
    )) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        . $candidate
        break
    }
}
if (-not (Get-Command Initialize-WinMintConsoleEncoding -ErrorAction SilentlyContinue)) {
    Write-Error "WinMint.Runtime.Common.ps1 is missing for WinMintAgent at '$agentRoot'."
    exit 1
}
Initialize-WinMintConsoleEncoding
$stateDir = Join-Path $env:LOCALAPPDATA 'WinMint'
$logDir = Join-Path $stateDir 'Logs'
$script:logDir = $logDir
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
$script:AgentConsoleSplashImagePath = Join-Path $agentRoot 'Assets\Brand\winmint_logo_wordmark.png'

. (Join-Path $agentRoot 'Agent.Context.ps1')
. (Join-Path $agentRoot 'Agent.Console.ps1')
. (Join-Path $agentRoot 'Agent.State.ps1')
. (Join-Path $agentRoot 'Agent.Host.ps1')
. (Join-Path $agentRoot 'Agent.Install.ps1')
. (Join-Path $agentRoot 'Agent.Plan.ps1')
. (Join-Path $agentRoot 'Agent.Runtime.ps1')

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
$targetArchitecture = if ($agentProfile.PSObject.Properties['targetArchitecture'] -and -not [string]::IsNullOrWhiteSpace([string]$agentProfile.targetArchitecture)) {
    [string]$agentProfile.targetArchitecture
} else {
    Get-AgentProcessorArchitecture
}
$script:AgentTargetArchitecture = $targetArchitecture
Set-WinMintAgentContext -Context (New-WinMintAgentContext @{
        AgentRoot = $agentRoot
        State = $state
        StatePath = $statePath
        AgentProfile = $agentProfile
        Manifest = $manifest
        Force = [bool]$Force
        LogDir = $logDir
        EventLogPath = $eventLogPath
        CommandLogDir = $commandLogDir
        StateDir = $stateDir
        ManifestPath = $manifestPath
        TargetArchitecture = $targetArchitecture
        Interactive = [bool]$InteractiveFirstLogon
        EmitProgressJson = [bool]$EmitProgressJson
    })

Write-AgentLog 'WinMintAgent start'
Write-AgentEvent -Type 'run' -Status 'starting' -Message 'WinMintAgent start'
Initialize-AgentConsole
Show-AgentConsoleHeader
Update-AgentProcessPath
# Dot-source each agent module HERE, at script scope, so its bootstrap function is visible
# to the step runtime later. Doing this inside a function would scope the functions to that
# function; they would vanish on return and every module step would fail "<fn> not found".
# (foreach does not create a scope, so the dot-source lands in script scope.)
foreach ($moduleDefinition in @(Get-WinMintAgentModuleCatalog)) {
    $modulePath = Join-Path $agentRoot $moduleDefinition.RelativePath
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        throw "FirstLogon module '$($moduleDefinition.Id)' is missing: $modulePath"
    }
    . $modulePath
    $bootstrapFunction = [string]$moduleDefinition.BootstrapFunction
    if (-not (Get-Command $bootstrapFunction -ErrorAction SilentlyContinue)) {
        throw "FirstLogon module '$($moduleDefinition.Id)' did not register required function '$bootstrapFunction'."
    }
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
    Write-AgentEvent -Type 'run' -Status 'failed' -Step 'manifest' -Message "Package manifest missing: $manifestPath"
    Wait-AgentConsoleBeforeClose -Failed $true
    exit 1
}

exit (Invoke-WinMintAgentStepRuntime)
