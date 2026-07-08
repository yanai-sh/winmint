#Requires -Version 7.6

function Invoke-WinMintAgentStepRuntime {
    $ctx = Get-WinMintAgentContext
    $state = $ctx.State
    $runtimePlan = @(New-WinMintAgentRuntimeStepPlan)
    foreach ($step in @($runtimePlan | Where-Object { $_.Phase -eq 'main' } | Sort-Object Order)) {
        Invoke-AgentProfileModule -StepName $step.StepName -FunctionName $step.FunctionName -Enabled ([bool]$step.Enabled) -PostStepHook ([string]$step.PostStepHook)
    }
    if (Test-AgentModuleEnabled -Name 'packageManagers') {
        Invoke-WinMintAgentWingetCatchUpAll -State $state
    }
    Remove-AgentDesktopShortcuts

    foreach ($step in @($runtimePlan | Where-Object { $_.Phase -eq 'finalValidation' } | Sort-Object Order)) {
        Invoke-AgentProfileModule -StepName $step.StepName -FunctionName $step.FunctionName -Enabled ([bool]$step.Enabled) -PostStepHook ([string]$step.PostStepHook)
    }

    # Live-user modules are best-effort. A failed app/tool install must not keep
    # autologon credentials resident or block final desktop personalization; the
    # summary and state file carry the retry/manual-repair details.
    $blockingSteps = @($runtimePlan | Where-Object { $_.FailurePolicy -eq 'blocking' } | ForEach-Object { [string]$_.Id })
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
        return 1
    }

    $rebootPending = Test-AgentRebootPending
    $needsRebootSteps = @($state.steps.GetEnumerator() | Where-Object { [string]$_.Value.status -eq 'needsReboot' } | ForEach-Object { [string]$_.Key })
    Set-AgentStateValue -State $state -Name 'completedAt' -Value (Get-Date -Format o)
    $warningSteps = @($advisoryFailed | ForEach-Object { [string]$_.Key })
    Set-AgentStateValue -State $state -Name 'run' -Value @{
        status = if ($needsRebootSteps.Count -gt 0) { 'needsReboot' } else { 'ok' }
        completedAt = (Get-Date -Format o)
        exitCode = 0
        rebootPending = $rebootPending
        needsReboot = ($needsRebootSteps.Count -gt 0)
        needsRebootSteps = $needsRebootSteps
        warningSteps = $warningSteps
    }
    Save-AgentState -State $state
    $message = if ($needsRebootSteps.Count -gt 0) { 'FirstLogon agent completed; reboot required to continue.' }
        elseif ($warningSteps.Count -gt 0) { 'FirstLogon agent completed with warnings.' }
        else { 'FirstLogon agent completed.' }
    Write-AgentEvent -Type 'run' -Status 'ok' -Message $message -Data @{
        rebootPending = $rebootPending
        needsReboot = ($needsRebootSteps.Count -gt 0)
        needsRebootSteps = $needsRebootSteps
        warningSteps = $warningSteps
    }
    if ($rebootPending) { Write-AgentLog 'Windows reports a pending reboot after the successful FirstLogon run.' }
    if ($warningSteps.Count -gt 0) { Write-AgentLog "WinMintAgent completed with warning step(s): $($warningSteps -join ', ')" }
    else { Write-AgentLog 'WinMintAgent end' }
    Show-AgentFinalSummary -State $state
    Wait-AgentConsoleBeforeClose -Failed $false -Warnings:($warningSteps.Count -gt 0)
    return 0
}

# NOTE: FirstLogon modules are registered through agent-module-catalog.json and
# loaded by Start-WinMintAgent.ps1. Keep the catalog aligned with the runtime
# step plan; do not fall back to folder globbing or function-scoped loaders that
# lose the exported bootstrap functions.
