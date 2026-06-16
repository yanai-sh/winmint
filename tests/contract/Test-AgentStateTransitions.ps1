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
. (Join-Path $root 'src\runtime\firstlogon\Modules\PackageManagers.ps1')
. (Join-Path $root 'src\runtime\firstlogon\Modules\LauncherKey.ps1')

function Install-AgentTool {
    param($Tool, [hashtable]$State)

    $key = "tool:$($Tool.id)"
    $State.steps[$key] = @{
        status = 'ok'
        updatedAt = (Get-Date -Format o)
        source = [string]$Tool.source
    }
    Save-AgentState -State $State
}

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

function Invoke-TestPostStepHook {
    param([object]$AgentProfile, [hashtable]$State)
    [void]$AgentProfile
    [void]$State
    $script:postStepHookCalls++
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('winmint-agent-state-test-' + [Guid]::NewGuid().ToString('n'))
try {
    $null = New-Item -ItemType Directory -Path $tempRoot -Force
    $script:statePath = Join-Path $tempRoot 'state.json'
    $script:agentProfile = [pscustomobject]@{
        targetArchitecture = 'arm64'
        browsers = @('firefox')
        editors = @('neovim')
        modules = [pscustomobject]@{
            packageManagers = [pscustomobject]@{ enabled = $true }
            wsl = [pscustomobject]@{ enabled = $true }
            git = [pscustomobject]@{ enabled = $true }
            dotfiles = [pscustomobject]@{ enabled = $true }
            raycast = [pscustomobject]@{ enabled = $true }
            launcherKey = [pscustomobject]@{ enabled = $true; target = 'Raycast'; chord = 'Win+Shift+F23' }
            phoneLink = [pscustomobject]@{ enabled = $true }
            shell = [pscustomobject]@{ enabled = $true }
            windhawk = [pscustomobject]@{ enabled = $true }
            liveInstallAudit = [pscustomobject]@{ enabled = $true }
        }
    }
    $script:AgentTargetArchitecture = 'arm64'
    $script:Force = $false
    $script:State = [ordered]@{
        version = 1
        steps = @{}
    }

    $runtimePlan = @(New-WinMintAgentRuntimeStepPlan)
    $expectedStepOrder = @(
        'profiles',
        'package-managers',
        'wsl',
        'git',
        'dotfiles',
        'raycast',
        'launcher-key',
        'phone-link',
        'tiling-desktop',
        'windhawk',
        'browsers',
        'editors',
        'liveInstallAudit'
    )
    Assert-Equal (@($runtimePlan | Sort-Object Order | ForEach-Object { $_.StepName }) -join ',') ($expectedStepOrder -join ',') 'Agent runtime step plan should preserve module order.'
    $profilesStep = $runtimePlan | Where-Object { $_.StepName -eq 'profiles' } | Select-Object -First 1
    $editorsStep = $runtimePlan | Where-Object { $_.StepName -eq 'editors' } | Select-Object -First 1
    $auditStep = $runtimePlan | Where-Object { $_.StepName -eq 'liveInstallAudit' } | Select-Object -First 1
    Assert-Equal $profilesStep.Id 'module:profiles' 'Agent runtime step ids should match state keys.'
    Assert-Equal $profilesStep.FailurePolicy 'blocking' 'Profile bootstrap should be the blocking FirstLogon step.'
    Assert-Equal $editorsStep.PostStepHook 'Set-WinMintAgentNeovimEnvironment' 'Editors should declare the Neovim environment post-step hook.'
    Assert-Equal $auditStep.Phase 'finalValidation' 'Live install audit should run during final validation.'
    Assert-Equal $auditStep.FailurePolicy 'advisory' 'Live install audit should remain advisory.'
    Assert-True ([bool]$runtimePlan[1].Enabled) 'Enabled module config should be reflected in the runtime plan.'
    $launcherKeyStep = $runtimePlan | Where-Object { $_.StepName -eq 'launcher-key' } | Select-Object -First 1
    Assert-Equal $launcherKeyStep.Enablement 'modules.launcherKey.enabled' 'Launcher key binding should be controlled by the launcherKey module.'

    $raycastKeyPlan = Get-WinMintAgentLauncherKeyPlan -AgentProfile $script:agentProfile
    Assert-Equal $raycastKeyPlan.Target 'Raycast' 'Launcher key plan should prefer explicit launcherKey target.'
    Assert-Equal $raycastKeyPlan.Chord 'Win+Shift+F23' 'Launcher key plan should preserve the common Copilot hardware-key chord.'

    $script:manifest = [pscustomobject]@{
        tools = [pscustomobject]@{
            firefox = [pscustomobject]@{
                id = 'Mozilla.Firefox'
                source = 'winget'
            }
            neovim = [pscustomobject]@{
                id = 'neovim'
                source = 'scoop'
            }
        }
    }
    $selection = Invoke-WinMintAgentManifestToolSelection -SelectionId 'browsers' -SelectedIds @('edge', 'firefox', 'missing-browser') -State $State -StateKeyPrefix 'browser' -ExcludedIds @('edge')
    Assert-Equal (@($selection.SelectedIds) -join ',') 'edge,firefox,missing-browser' 'Package selection should preserve selected ids.'
    Assert-Equal (@($selection.InstallIds) -join ',') 'firefox,missing-browser' 'Package selection should omit excluded ids from installs.'
    Assert-Equal (@($selection.ExcludedIds) -join ',') 'edge' 'Package selection should surface excluded ids.'
    Assert-Equal (@($selection.UnknownIds) -join ',') 'missing-browser' 'Package selection should surface unknown ids.'
    Assert-Equal $selection.ToolResults[0].Source 'winget' 'Package selection should expose package source ownership.'
    Assert-Equal $selection.ToolResults[0].StateKey 'tool:Mozilla.Firefox' 'Package selection should expose tool state key naming.'
    Assert-Equal $State.steps['browser:missing-browser'].status 'failed' 'Unknown selected package ids should write the domain state key.'

    Invoke-AgentProfileModule -StepName 'disabled' -FunctionName 'Invoke-TestAgentOkModule' -Enabled $false
    Assert-Equal $State.steps['module:disabled'].status 'skipped' 'Disabled modules should persist skipped status.'
    Assert-True (Test-Path -LiteralPath $statePath) 'Save-AgentState should create state.json for skipped modules.'

    Invoke-AgentProfileModule -StepName 'ok-step' -FunctionName 'Invoke-TestAgentOkModule' -Enabled $true
    Assert-Equal $State.steps['module:ok-step'].status 'ok' 'Successful modules should persist ok status.'
    Assert-Equal $State.steps['module:ok-step'].attempts 1 'Successful modules should record first attempt.'
    Assert-Equal $State.steps['module:ok-step'].result.Marker 'ok-result' 'Successful modules should persist result payload.'

    $script:postStepHookCalls = 0
    Invoke-AgentProfileModule -StepName 'hook-step' -FunctionName 'Invoke-TestAgentOkModule' -Enabled $true -PostStepHook 'Invoke-TestPostStepHook'
    Assert-Equal $script:postStepHookCalls 1 'Successful modules should invoke their post-step hook.'
    Invoke-AgentProfileModule -StepName 'hook-step' -FunctionName 'Invoke-TestAgentFailedModule' -Enabled $true -PostStepHook 'Invoke-TestPostStepHook'
    Assert-Equal $script:postStepHookCalls 2 'Idempotently skipped completed modules should still invoke their post-step hook.'

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
