#Requires -Version 5.1

function New-WinMintFirstLogonTransactionStep {
    param(
        [Parameter(Mandatory)][int]$Order,
        [Parameter(Mandatory)][string]$Id,
        [ValidateSet('blocking', 'bestEffort', 'conditional')][string]$FailurePolicy = 'bestEffort',
        [string]$Condition = 'always'
    )

    [pscustomobject]@{
        Order = $Order
        Id = $Id
        FailurePolicy = $FailurePolicy
        Condition = $Condition
    }
}

function New-WinMintFirstLogonTransactionPlan {
    [CmdletBinding()]
    param(
        [ValidateSet('Auto','UI','Console','Headless')]
        [string]$AgentMode = 'Auto'
    )

    [void]$AgentMode
    $steps = [System.Collections.Generic.List[object]]::new()
    $order = 0

    $order++
    $steps.Add((New-WinMintFirstLogonTransactionStep `
                -Order $order `
                -Id 'prepare-host' `
                -FailurePolicy 'blocking')) | Out-Null

    $order++
    $steps.Add((New-WinMintFirstLogonTransactionStep `
                -Order $order `
                -Id 'persist-retry-autologon' `
                -FailurePolicy 'bestEffort')) | Out-Null

    $order++
    $steps.Add((New-WinMintFirstLogonTransactionStep `
                -Order $order `
                -Id 'restore-visible-user-posture' `
                -FailurePolicy 'bestEffort')) | Out-Null

    $order++
    $steps.Add((New-WinMintFirstLogonTransactionStep `
                -Order $order `
                -Id 'apply-live-user-defaults' `
                -FailurePolicy 'bestEffort')) | Out-Null

    $order++
    $steps.Add((New-WinMintFirstLogonTransactionStep `
                -Order $order `
                -Id 'launch-agent' `
                -FailurePolicy 'blocking')) | Out-Null

    $order++
    $steps.Add((New-WinMintFirstLogonTransactionStep `
                -Order $order `
                -Id 'finalize-user-shell' `
                -FailurePolicy 'bestEffort' `
                -Condition 'agent-script-staged')) | Out-Null

    $order++
    $steps.Add((New-WinMintFirstLogonTransactionStep `
                -Order $order `
                -Id 'finalize-success' `
                -FailurePolicy 'conditional' `
                -Condition 'agentExitCode == 0')) | Out-Null

    $order++
    $steps.Add((New-WinMintFirstLogonTransactionStep `
                -Order $order `
                -Id 'finalize-recovery' `
                -FailurePolicy 'conditional' `
                -Condition 'agentExitCode != 0')) | Out-Null

    return @($steps)
}

function Test-WinMintFirstLogonTransactionCondition {
    param(
        [Parameter(Mandatory)][string]$Condition,
        [Parameter(Mandatory)][hashtable]$Context
    )

    switch ($Condition) {
        'always' { return $true }
        'agent-script-staged' { return [bool]$Context.AgentScriptStaged }
        'agentExitCode == 0' { return ([int]$Context.AgentExitCode -eq 0) }
        'agentExitCode != 0' { return ([int]$Context.AgentExitCode -ne 0) }
        default { throw "Unsupported FirstLogon transaction condition: $Condition" }
    }
}

function Write-WinMintFirstLogonTransactionAdapterError {
    param(
        [Parameter(Mandatory)][object]$Step,
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $message = "FirstLogon transaction step '$($Step.Id)' failed: $($ErrorRecord.Exception.Message)"
    if (Get-Command Write-WinMintFirstLogonError -ErrorAction SilentlyContinue) {
        Write-WinMintFirstLogonError $message
    }
    else {
        Write-Warning $message
    }
}

function Invoke-WinMintFirstLogonTransactionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Plan,
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][hashtable]$StepAdapters
    )

    foreach ($step in @($Plan | Sort-Object Order)) {
        if (-not (Test-WinMintFirstLogonTransactionCondition -Condition ([string]$step.Condition) -Context $Context)) {
            continue
        }

        if (-not $StepAdapters.ContainsKey([string]$step.Id)) {
            throw "No FirstLogon transaction adapter registered for step '$($step.Id)'."
        }

        try {
            $null = & $StepAdapters[[string]$step.Id] -Context $Context -Step $step
        }
        catch {
            if ([string]$step.FailurePolicy -eq 'blocking') {
                throw
            }
            Write-WinMintFirstLogonTransactionAdapterError -Step $step -ErrorRecord $_
        }
    }

    return $Context
}

function Invoke-WinMintFirstLogonAgentLaunch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Auto','UI','Console','Headless')]
        [string]$AgentMode,
        [Parameter(Mandatory)][string]$AgentRoot,
        [Parameter(Mandatory)][string]$AgentPath
    )

    [void]$AgentRoot
    if (-not (Test-Path -LiteralPath $AgentPath)) {
        Write-WinMintFirstLogonError "WinMintAgent script was not found: $AgentPath"
        return 1
    }

    $agentExitCode = 0
    try {
        $exe = Resolve-WinMintPowerShellHost
        # The agent is the source of truth and does all first-logon work. Default is a
        # visible console so the user can see progress while the automation runs.
        $mode = Resolve-WinMintFirstLogonAgentMode -RequestedMode $AgentMode
        "$(Get-Date -Format 'o') Launching WinMintAgent in $mode mode" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
        if ($mode -eq 'Console') {
            "$(Get-Date -Format 'o') Waiting for Windows Terminal before launching WinMintAgent." | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
            $terminal = Wait-WinMintWindowsTerminalHost -TimeoutSeconds 120
            if (-not [string]::IsNullOrWhiteSpace($terminal)) {
                $agentExitCode = Start-WinMintFirstLogonAgentInTerminal `
                    -TerminalPath $terminal `
                    -PowerShellPath $exe `
                    -AgentPath $AgentPath
            }
            else {
                Write-WinMintFirstLogonError 'Windows Terminal was not available; falling back to a visible PowerShell console for WinMintAgent.'
                $agentProcess = Start-Process -FilePath $exe -ArgumentList @(
                    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                    '-File', "`"$AgentPath`"", '-InteractiveFirstLogon'
                ) -WindowStyle Normal -Wait -PassThru
                $agentExitCode = [int]$agentProcess.ExitCode
            }
        }
        else {
            # Headless mode stays available for automation, but it is opt-in now.
            $agentProcess = Start-Process -FilePath $exe -ArgumentList @(
                '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', "`"$AgentPath`""
            ) -WindowStyle Hidden -Wait -PassThru
            $agentExitCode = [int]$agentProcess.ExitCode
        }
        if ($agentExitCode -ne 0) { Write-WinMintFirstLogonError "WinMintAgent exited with code $agentExitCode" }
    }
    catch {
        $agentExitCode = 1
        Write-WinMintFirstLogonError "WinMintAgent launch failed: $_"
    }

    return $agentExitCode
}
