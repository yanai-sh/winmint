#Requires -Version 7.6
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

function Assert-Throws {
    param(
        [scriptblock]$ScriptBlock,
        [string]$Message
    )

    $threw = $false
    try {
        & $ScriptBlock
    }
    catch {
        $threw = $true
    }

    if (-not $threw) { Add-Failure $Message }
}

function Write-WinMintFirstLogonError {
    param([string]$Message)

    [void]$Message
}

. (Join-Path $root 'src\runtime\setup\FirstLogon.Transaction.ps1')

$plan = @(New-WinMintFirstLogonTransactionPlan -AgentMode Console)
$expectedOrder = @(
    'prepare-host',
    'persist-retry-autologon',
    'restore-visible-user-posture',
    'apply-live-user-defaults',
    'launch-agent',
    'finalize-user-shell',
    'finalize-success',
    'finalize-recovery'
)

Assert-Equal (@($plan | Sort-Object Order | ForEach-Object { $_.Id }) -join ',') ($expectedOrder -join ',') 'FirstLogon transaction plan should preserve phase order.'

$restore = $plan | Where-Object { $_.Id -eq 'restore-visible-user-posture' } | Select-Object -First 1
$defaults = $plan | Where-Object { $_.Id -eq 'apply-live-user-defaults' } | Select-Object -First 1
$agent = $plan | Where-Object { $_.Id -eq 'launch-agent' } | Select-Object -First 1
$shell = $plan | Where-Object { $_.Id -eq 'finalize-user-shell' } | Select-Object -First 1
$success = $plan | Where-Object { $_.Id -eq 'finalize-success' } | Select-Object -First 1
$recovery = $plan | Where-Object { $_.Id -eq 'finalize-recovery' } | Select-Object -First 1

Assert-True ($restore.Order -lt $defaults.Order) 'DMA visible-posture restore should run before live-user defaults and cleanup.'
Assert-True ($agent.Order -lt $shell.Order) 'Agent launch should run before final terminal profile and Start pin finalization.'
Assert-True ($shell.Order -lt $success.Order) 'User-shell finalization should happen before success cleanup.'
Assert-Equal $plan[0].FailurePolicy 'blocking' 'FirstLogon state initialization should be a blocking transaction step.'
Assert-Equal $agent.FailurePolicy 'blocking' 'Agent launch should be a blocking transaction step.'
Assert-Equal $success.Condition 'agentExitCode == 0' 'Success cleanup should be gated on successful agent exit.'
Assert-Equal $recovery.Condition 'agentExitCode != 0' 'Recovery handling should be gated on failed/incomplete agent exit.'

function New-TestTransactionAdapters {
    param(
        [int]$AgentExitCode = 0,
        [string]$ThrowStep = ''
    )

    $adapters = @{}
    foreach ($stepId in $expectedOrder) {
        $localStepId = $stepId
        $adapters[$localStepId] = {
            param([hashtable]$Context, $Step)
            [void]$Step
            $Context.Calls.Add($localStepId) | Out-Null
            if ($localStepId -eq $ThrowStep) {
                throw "fixture failure: $localStepId"
            }
            if ($localStepId -eq 'launch-agent') {
                $Context.AgentExitCode = $AgentExitCode
            }
        }.GetNewClosure()
    }
    return $adapters
}

$successContext = @{
    AgentScriptStaged = $true
    AgentExitCode = 1
    Calls = [System.Collections.Generic.List[string]]::new()
}
Invoke-WinMintFirstLogonTransactionPlan `
    -Plan $plan `
    -Context $successContext `
    -StepAdapters (New-TestTransactionAdapters -AgentExitCode 0) | Out-Null
Assert-Equal ($successContext.Calls -join ',') 'prepare-host,persist-retry-autologon,restore-visible-user-posture,apply-live-user-defaults,launch-agent,finalize-user-shell,finalize-success' 'Successful transaction should execute success cleanup and skip recovery.'

$recoveryContext = @{
    AgentScriptStaged = $true
    AgentExitCode = 0
    Calls = [System.Collections.Generic.List[string]]::new()
}
Invoke-WinMintFirstLogonTransactionPlan `
    -Plan $plan `
    -Context $recoveryContext `
    -StepAdapters (New-TestTransactionAdapters -AgentExitCode 5) | Out-Null
Assert-Equal ($recoveryContext.Calls -join ',') 'prepare-host,persist-retry-autologon,restore-visible-user-posture,apply-live-user-defaults,launch-agent,finalize-user-shell,finalize-recovery' 'Failed agent transaction should execute recovery and skip success cleanup.'

$missingAgentContext = @{
    AgentScriptStaged = $false
    AgentExitCode = 1
    Calls = [System.Collections.Generic.List[string]]::new()
}
Invoke-WinMintFirstLogonTransactionPlan `
    -Plan $plan `
    -Context $missingAgentContext `
    -StepAdapters (New-TestTransactionAdapters -AgentExitCode 0) | Out-Null
Assert-Equal ($missingAgentContext.Calls -join ',') 'prepare-host,persist-retry-autologon,restore-visible-user-posture,apply-live-user-defaults,launch-agent,finalize-success' 'Transaction should skip user-shell finalization when the agent script is not staged.'

$bestEffortContext = @{
    AgentScriptStaged = $true
    AgentExitCode = 1
    Calls = [System.Collections.Generic.List[string]]::new()
}
Invoke-WinMintFirstLogonTransactionPlan `
    -Plan $plan `
    -Context $bestEffortContext `
    -StepAdapters (New-TestTransactionAdapters -AgentExitCode 0 -ThrowStep 'apply-live-user-defaults') | Out-Null
Assert-True (@($bestEffortContext.Calls) -contains 'launch-agent') 'Best-effort transaction failures should not stop later steps.'

$blockingContext = @{
    AgentScriptStaged = $true
    AgentExitCode = 1
    Calls = [System.Collections.Generic.List[string]]::new()
}
Assert-Throws {
    Invoke-WinMintFirstLogonTransactionPlan `
        -Plan $plan `
        -Context $blockingContext `
        -StepAdapters (New-TestTransactionAdapters -AgentExitCode 0 -ThrowStep 'launch-agent') | Out-Null
} 'Blocking transaction failures should propagate.'

if ($failures.Count -gt 0) {
    throw "FirstLogon transaction plan tests failed with $($failures.Count) failure(s)."
}

Write-Host 'FirstLogon transaction plan tests passed.'

