#Requires -Version 7.3
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)

    $failures.Add($Message) | Out-Null
    Write-Error $Message -ErrorAction Continue
}

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
    )

    if ([string]$Actual -ne [string]$Expected) {
        Add-Failure "$Message Expected '$Expected', got '$Actual'."
    }
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) { Add-Failure $Message }
}

function Write-AgentLog { param([string]$Message) [void]$Message }
function Write-AgentEvent {
    param(
        [string]$Type,
        [string]$Status,
        [string]$Step,
        [string]$Message,
        [hashtable]$Data = @{}
    )
    [void]$Type
    [void]$Status
    [void]$Step
    [void]$Message
    [void]$Data
}
function Write-AgentConsoleLine { param([string]$Level, [string]$Message) [void]$Level; [void]$Message }

. (Join-Path $root 'src\runtime\firstlogon\Agent.Runtime.ps1')

$nativePreferredTool = [pscustomobject]@{
    architectures = @('amd64', 'arm64')
    wingetArchitectureByHost = [pscustomobject]@{
        arm64 = 'x86'
    }
}
Assert-Equal (Get-AgentToolWingetArchitecture -Tool $nativePreferredTool -HostArchitecture 'arm64' -TargetArchitecture 'arm64') 'arm64' 'Native ARM64 support must win over stale x86 overrides.'

$x64Tool = [pscustomobject]@{
    architectures = @('amd64', 'arm64')
}
Assert-Equal (Get-AgentToolWingetArchitecture -Tool $x64Tool -HostArchitecture 'amd64' -TargetArchitecture 'amd64') '' 'amd64 targets should use package-manager default architecture without a winget override.'
Assert-Equal (Get-AgentToolWingetArchitecture -Tool $x64Tool -HostArchitecture 'arm64' -TargetArchitecture 'arm64') 'arm64' 'ARM64 targets should request native arm64 winget packages when supported.'

function Invoke-TestAgentOkModule {
    param([object]$AgentProfile, [hashtable]$State)
    [void]$AgentProfile
    [void]$State
    [pscustomobject]@{ Status = 'ok'; Marker = 'ok-result' }
}

function Invoke-TestAgentNeedsRebootModule {
    param([object]$AgentProfile, [hashtable]$State)
    [void]$AgentProfile
    [void]$State
    [pscustomobject]@{ Status = 'needsReboot'; Marker = 'reboot-result' }
}

function Invoke-TestAgentFailedModule {
    param([object]$AgentProfile, [hashtable]$State)
    [void]$AgentProfile
    [void]$State
    throw 'fixture failure'
}

function Invoke-TestLiveAuditFindingsModule {
    param([object]$AgentProfile, [hashtable]$State)
    [void]$AgentProfile
    [void]$State
    [pscustomobject]@{
        Status = 'ok'
        Summary = [pscustomobject]@{
            error = 2
            warning = 3
        }
    }
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('winmint-agent-state-test-' + [Guid]::NewGuid().ToString('n'))
try {
    $null = New-Item -ItemType Directory -Path $tempRoot -Force
    $script:statePath = Join-Path $tempRoot 'state.json'
    $script:agentProfile = [pscustomobject]@{
        targetArchitecture = 'arm64'
        modules = [pscustomobject]@{
            packageManagers = [pscustomobject]@{ enabled = $true }
        }
    }
    $script:AgentTargetArchitecture = 'arm64'
    $script:Force = $false
    $script:State = [ordered]@{
        version = 1
        steps = @{}
    }

    Invoke-AgentProfileModule -StepName 'disabled' -FunctionName 'Invoke-TestAgentOkModule' -Enabled $false
    Assert-Equal $State.steps['module:disabled'].status 'skipped' 'Disabled modules should persist skipped status.'
    Assert-True (Test-Path -LiteralPath $statePath) 'Save-AgentState should create state.json for skipped modules.'

    Invoke-AgentProfileModule -StepName 'ok-step' -FunctionName 'Invoke-TestAgentOkModule' -Enabled $true
    Assert-Equal $State.steps['module:ok-step'].status 'ok' 'Successful modules should persist ok status.'
    Assert-Equal $State.steps['module:ok-step'].attempts 1 'Successful modules should record first attempt.'
    Assert-Equal $State.steps['module:ok-step'].result.Marker 'ok-result' 'Successful modules should persist result payload.'

    Invoke-AgentProfileModule -StepName 'ok-step' -FunctionName 'Invoke-TestAgentFailedModule' -Enabled $true
    Assert-Equal $State.steps['module:ok-step'].status 'ok' 'Completed modules should be idempotently skipped without Force.'
    Assert-Equal $State.steps['module:ok-step'].attempts 1 'Completed modules should not increment attempts without Force.'

    $script:Force = $true
    Invoke-AgentProfileModule -StepName 'ok-step' -FunctionName 'Invoke-TestAgentOkModule' -Enabled $true
    Assert-Equal $State.steps['module:ok-step'].attempts 2 'Force should re-run completed modules and increment attempts.'
    $script:Force = $false

    Invoke-AgentProfileModule -StepName 'reboot-step' -FunctionName 'Invoke-TestAgentNeedsRebootModule' -Enabled $true
    Assert-Equal $State.steps['module:reboot-step'].status 'needsReboot' 'Modules should persist needsReboot status for retry after reboot.'
    Assert-Equal $State.steps['module:reboot-step'].attempts 1 'needsReboot modules should record attempts.'

    Invoke-AgentProfileModule -StepName 'reboot-step' -FunctionName 'Invoke-TestAgentOkModule' -Enabled $true
    Assert-Equal $State.steps['module:reboot-step'].status 'ok' 'needsReboot modules should be retried on the next run.'
    Assert-Equal $State.steps['module:reboot-step'].attempts 2 'Retried needsReboot modules should increment attempts.'

    Invoke-AgentProfileModule -StepName 'failed-step' -FunctionName 'Invoke-TestAgentFailedModule' -Enabled $true
    Assert-Equal $State.steps['module:failed-step'].status 'failed' 'Throwing modules should persist failed status.'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$State.steps['module:failed-step'].error)) 'Failed modules should persist error text.'

    Invoke-AgentProfileModule -StepName 'liveInstallAudit' -FunctionName 'Invoke-TestLiveAuditFindingsModule' -Enabled $true
    Assert-Equal $State.steps['module:liveInstallAudit'].status 'ok' 'Live audit findings should not fail the FirstLogon agent state.'
    Assert-Equal $State.steps['module:liveInstallAudit'].result.Summary.error 2 'Live audit result should preserve error count for diagnostics.'

    $saved = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    Assert-Equal $saved.steps.'module:ok-step'.status 'ok' 'Saved state should round-trip ok module status.'
    Assert-Equal $saved.steps.'module:reboot-step'.attempts 2 'Saved state should round-trip retry attempts.'
    Assert-Equal $saved.steps.'module:liveInstallAudit'.status 'ok' 'Saved state should keep live audit diagnostic failures non-blocking.'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    throw "Agent state transition tests failed with $($failures.Count) failure(s)."
}

Write-Host 'Agent state transition tests passed.'
