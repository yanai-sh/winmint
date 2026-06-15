#Requires -Version 7.3
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$InteractiveFirstLogon,
    [switch]$EmitProgressJson
)

$ErrorActionPreference = 'Continue'

function Initialize-WinMintAgentConsoleEncoding {
    try {
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [Console]::InputEncoding = $utf8
        [Console]::OutputEncoding = $utf8
        $global:OutputEncoding = $utf8
        $global:PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
        $global:PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
        $global:PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
    }
    catch { }
    try {
        $chcpExe = Join-Path $env:SystemRoot 'System32\chcp.com'
        $null = & $chcpExe 65001 2>$null
    }
    catch { }
}

Initialize-WinMintAgentConsoleEncoding
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
$script:AgentConsoleSplashImagePath = Join-Path $agentRoot 'Assets\Brand\winmint_logo_wordmark.png'

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

exit (Invoke-WinMintAgentStepRuntime)
