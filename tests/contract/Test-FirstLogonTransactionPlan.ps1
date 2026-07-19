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

function Resolve-WinMintFirstLogonAgentMode {
    param([Parameter(Mandatory)][string]$RequestedMode)

    if ($RequestedMode -in @('Console', 'Headless')) { return 'Debug' }
    return 'Normal'
}

function Test-WinMintFirstLogonUsesProvisioningHost {
    param([Parameter(Mandatory)][string]$AgentMode)

    return (Resolve-WinMintFirstLogonAgentMode -RequestedMode $AgentMode) -eq 'Normal'
}

. (Join-Path $root 'src\runtime\setup\FirstLogon.Transaction.ps1')

$plan = @(New-WinMintFirstLogonTransactionPlan -AgentMode Console)
$expectedOrder = @(
    'bootstrap-session',
    'engage-provisioning-lock',
    'prepare-host',
    'persist-retry-autologon',
    'restore-visible-user-posture',
    'apply-live-user-defaults',
    'run-agent',
    'finalize-desktop-under-lock',
    'finalize-reboot-resume',
    'release-provisioning-lock',
    'finalize-success',
    'finalize-recovery'
)

Assert-Equal (@($plan | Sort-Object Order | ForEach-Object { $_.Id }) -join ',') ($expectedOrder -join ',') 'FirstLogon transaction plan should preserve phase order.'

$engage = $plan | Where-Object { $_.Id -eq 'engage-provisioning-lock' } | Select-Object -First 1
$restore = $plan | Where-Object { $_.Id -eq 'restore-visible-user-posture' } | Select-Object -First 1
$defaults = $plan | Where-Object { $_.Id -eq 'apply-live-user-defaults' } | Select-Object -First 1
$agent = $plan | Where-Object { $_.Id -eq 'run-agent' } | Select-Object -First 1
$shell = $plan | Where-Object { $_.Id -eq 'finalize-desktop-under-lock' } | Select-Object -First 1
$release = $plan | Where-Object { $_.Id -eq 'release-provisioning-lock' } | Select-Object -First 1
$success = $plan | Where-Object { $_.Id -eq 'finalize-success' } | Select-Object -First 1
$rebootResume = $plan | Where-Object { $_.Id -eq 'finalize-reboot-resume' } | Select-Object -First 1
$recovery = $plan | Where-Object { $_.Id -eq 'finalize-recovery' } | Select-Object -First 1

$prepare = $plan | Where-Object { $_.Id -eq 'prepare-host' } | Select-Object -First 1
Assert-True ($engage.Order -lt $prepare.Order) 'Provisioning lock should engage before prepare-host.'
Assert-True ($engage.Order -lt $restore.Order) 'Provisioning lock should engage before regional restore.'
Assert-True ($restore.Order -lt $defaults.Order) 'DMA visible-posture restore should run before live-user defaults and cleanup.'
Assert-True ($agent.Order -lt $shell.Order) 'Agent run should complete before desktop finalization under lock.'
Assert-True ($shell.Order -lt $rebootResume.Order) 'Desktop finalization should run before under-lock reboot scheduling.'
Assert-True ($rebootResume.Order -lt $release.Order) 'needsReboot reboot scheduling must run under the provisioning lock (before release).'
Assert-True ($release.Order -lt $success.Order) 'Provisioning lock release should happen before success cleanup.'
Assert-Equal $engage.Condition 'provisioningHost' 'Engage step should be gated on provisioning host mode.'
Assert-Equal $release.Condition 'provisioningHost' 'Release step should be gated on provisioning host mode.'
Assert-Equal $plan[1].FailurePolicy 'blocking' 'FirstLogon state initialization should be a blocking transaction step.'
Assert-Equal $restore.FailurePolicy 'bestEffort' 'DMA visible-posture restore stays bestEffort so provisioning-lock release can still run; Runtime marks hard failure via DmaRestoreFailed.'
Assert-Equal $agent.FailurePolicy 'blocking' 'Agent run should be a blocking transaction step.'
Assert-Equal $success.Condition 'agentExitCode == 0 && !agentNeedsReboot' 'Success cleanup should be gated on successful agent exit without needsReboot.'
Assert-Equal $rebootResume.Condition 'agentExitCode == 0 && agentNeedsReboot' 'Reboot resume should run when the agent exits 0 with needsReboot steps.'
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
            if ($localStepId -eq 'run-agent') {
                $Context.AgentExitCode = $AgentExitCode
            }
        }.GetNewClosure()
    }
    return $adapters
}

$successContext = @{
    AgentMode = 'Console'
    AgentScriptStaged = $true
    AgentExitCode = 1
    AgentNeedsReboot = $false
    Calls = [System.Collections.Generic.List[string]]::new()
}
Invoke-WinMintFirstLogonTransactionPlan `
    -Plan $plan `
    -Context $successContext `
    -StepAdapters (New-TestTransactionAdapters -AgentExitCode 0) | Out-Null
Assert-Equal ($successContext.Calls -join ',') 'bootstrap-session,prepare-host,persist-retry-autologon,restore-visible-user-posture,apply-live-user-defaults,run-agent,finalize-desktop-under-lock,finalize-success' 'Successful transaction should execute success cleanup and skip recovery.'

$rebootContext = @{
    AgentMode = 'Console'
    AgentScriptStaged = $true
    AgentExitCode = 0
    AgentNeedsReboot = $true
    Calls = [System.Collections.Generic.List[string]]::new()
}
Invoke-WinMintFirstLogonTransactionPlan `
    -Plan $plan `
    -Context $rebootContext `
    -StepAdapters (New-TestTransactionAdapters -AgentExitCode 0) | Out-Null
Assert-Equal ($rebootContext.Calls -join ',') 'bootstrap-session,prepare-host,persist-retry-autologon,restore-visible-user-posture,apply-live-user-defaults,run-agent,finalize-desktop-under-lock,finalize-reboot-resume' 'needsReboot transaction should reboot-resume and skip success cleanup.'

$recoveryContext = @{
    AgentMode = 'Console'
    AgentScriptStaged = $true
    AgentExitCode = 0
    AgentNeedsReboot = $false
    Calls = [System.Collections.Generic.List[string]]::new()
}
Invoke-WinMintFirstLogonTransactionPlan `
    -Plan $plan `
    -Context $recoveryContext `
    -StepAdapters (New-TestTransactionAdapters -AgentExitCode 5) | Out-Null
Assert-Equal ($recoveryContext.Calls -join ',') 'bootstrap-session,prepare-host,persist-retry-autologon,restore-visible-user-posture,apply-live-user-defaults,run-agent,finalize-desktop-under-lock,finalize-recovery' 'Failed agent transaction should execute recovery and skip success cleanup.'

$missingAgentContext = @{
    AgentMode = 'Console'
    AgentScriptStaged = $false
    AgentExitCode = 1
    AgentNeedsReboot = $false
    Calls = [System.Collections.Generic.List[string]]::new()
}
Invoke-WinMintFirstLogonTransactionPlan `
    -Plan $plan `
    -Context $missingAgentContext `
    -StepAdapters (New-TestTransactionAdapters -AgentExitCode 0) | Out-Null
Assert-Equal ($missingAgentContext.Calls -join ',') 'bootstrap-session,prepare-host,persist-retry-autologon,restore-visible-user-posture,apply-live-user-defaults,run-agent,finalize-success' 'Transaction should skip desktop finalization when the agent script is not staged.'

$bestEffortContext = @{
    AgentMode = 'Console'
    AgentScriptStaged = $true
    AgentExitCode = 1
    AgentNeedsReboot = $false
    Calls = [System.Collections.Generic.List[string]]::new()
}
Invoke-WinMintFirstLogonTransactionPlan `
    -Plan $plan `
    -Context $bestEffortContext `
    -StepAdapters (New-TestTransactionAdapters -AgentExitCode 0 -ThrowStep 'apply-live-user-defaults') | Out-Null
Assert-True (@($bestEffortContext.Calls) -contains 'run-agent') 'Best-effort transaction failures should not stop later steps.'

$blockingContext = @{
    AgentMode = 'Console'
    AgentScriptStaged = $true
    AgentExitCode = 1
    AgentNeedsReboot = $false
    Calls = [System.Collections.Generic.List[string]]::new()
}
Assert-Throws {
    Invoke-WinMintFirstLogonTransactionPlan `
        -Plan $plan `
        -Context $blockingContext `
        -StepAdapters (New-TestTransactionAdapters -AgentExitCode 0 -ThrowStep 'run-agent') | Out-Null
} 'Blocking transaction failures should propagate.'

$hostPlan = @(New-WinMintFirstLogonTransactionPlan -AgentMode Auto)
$hostContext = @{
    AgentMode = 'Auto'
    AgentScriptStaged = $true
    AgentExitCode = 1
    AgentNeedsReboot = $false
    Calls = [System.Collections.Generic.List[string]]::new()
}
Invoke-WinMintFirstLogonTransactionPlan `
    -Plan $hostPlan `
    -Context $hostContext `
    -StepAdapters (New-TestTransactionAdapters -AgentExitCode 0) | Out-Null
Assert-True (@($hostContext.Calls) -contains 'engage-provisioning-lock') 'Auto mode should engage provisioning lock.'
Assert-True (@($hostContext.Calls) -contains 'release-provisioning-lock') 'Auto mode should release provisioning lock.'

$hostRebootContext = @{
    AgentMode = 'Auto'
    AgentScriptStaged = $true
    AgentExitCode = 0
    AgentNeedsReboot = $true
    Calls = [System.Collections.Generic.List[string]]::new()
}
Invoke-WinMintFirstLogonTransactionPlan `
    -Plan $hostPlan `
    -Context $hostRebootContext `
    -StepAdapters (New-TestTransactionAdapters -AgentExitCode 0) | Out-Null
$rebootIdx = @($hostRebootContext.Calls).IndexOf('finalize-reboot-resume')
$releaseIdx = @($hostRebootContext.Calls).IndexOf('release-provisioning-lock')
Assert-True ($rebootIdx -ge 0 -and $releaseIdx -ge 0 -and $rebootIdx -lt $releaseIdx) 'Auto needsReboot must schedule reboot under lock before release.'

$runtimeText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\FirstLogon.Runtime.ps1') -Raw
foreach ($expected in @('agentRebootCount', 'rebootLoop', 'rebootScheduledUnderLock', 'maxAgentReboots')) {
    if ($runtimeText -notmatch [regex]::Escape($expected)) {
        Add-Failure "FirstLogon reboot-resume should persist/guard '$expected'."
    }
}

$smokeProfile = Get-Content -LiteralPath (Join-Path $root 'tests\profiles\hyper-v-smoke-arm64.json') -Raw | ConvertFrom-Json
$sl7Profile = Get-Content -LiteralPath (Join-Path $root 'tests\profiles\hyper-v-sl7-smoke-arm64.json') -Raw | ConvertFrom-Json
if ([string]$smokeProfile.diagnostics.wslRuntimeValidation -ne 'skip' -or [string]$sl7Profile.diagnostics.wslRuntimeValidation -ne 'skip') {
    Add-Failure 'Hyper-V smoke profiles must keep diagnostics.wslRuntimeValidation=skip.'
}

if ($failures.Count -gt 0) {
    throw "FirstLogon transaction plan tests failed with $($failures.Count) failure(s)."
}

Write-Host 'FirstLogon transaction plan tests passed.'
