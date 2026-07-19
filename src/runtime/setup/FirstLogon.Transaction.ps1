#Requires -Version 5.1

function Get-WinMintFirstLogonTransactionStepCatalog {
    # ponytail: ordered step array; step IDs are contract-tested in Test-FirstLogonTransactionPlan.ps1.
    @(
        @{ Order = 1; Id = 'bootstrap-session'; FailurePolicy = 'blocking'; Condition = 'always' }
        @{ Order = 2; Id = 'engage-provisioning-lock'; FailurePolicy = 'blocking'; Condition = 'provisioningHost' }
        @{ Order = 3; Id = 'prepare-host'; FailurePolicy = 'blocking'; Condition = 'always' }
        @{ Order = 4; Id = 'persist-retry-autologon'; FailurePolicy = 'bestEffort'; Condition = 'always' }
        @{ Order = 5; Id = 'restore-visible-user-posture'; FailurePolicy = 'bestEffort'; Condition = 'always' }
        @{ Order = 6; Id = 'apply-live-user-defaults'; FailurePolicy = 'bestEffort'; Condition = 'always' }
        @{ Order = 7; Id = 'run-agent'; FailurePolicy = 'blocking'; Condition = 'always' }
        @{ Order = 8; Id = 'finalize-desktop-under-lock'; FailurePolicy = 'bestEffort'; Condition = 'agent-script-staged' }
        # Schedule reboot while the provisioning lock/presenter still owns the desktop.
        @{ Order = 9; Id = 'finalize-reboot-resume'; FailurePolicy = 'bestEffort'; Condition = 'agentExitCode == 0 && agentNeedsReboot' }
        @{ Order = 10; Id = 'release-provisioning-lock'; FailurePolicy = 'blocking'; Condition = 'provisioningHost' }
        @{ Order = 11; Id = 'finalize-success'; FailurePolicy = 'conditional'; Condition = 'agentExitCode == 0 && !agentNeedsReboot' }
        @{ Order = 12; Id = 'finalize-recovery'; FailurePolicy = 'conditional'; Condition = 'agentExitCode != 0' }
    ) | ForEach-Object { [pscustomobject]$_ }
}

function New-WinMintFirstLogonTransactionPlan {
    [CmdletBinding()]
    param(
        [ValidateSet('Auto','UI','Console','Headless','SetupShell')]
        [string]$AgentMode = 'Auto'
    )

    [void]$AgentMode
    return @(Get-WinMintFirstLogonTransactionStepCatalog)
}

function Test-WinMintFirstLogonTransactionCondition {
    param(
        [Parameter(Mandatory)][string]$Condition,
        [Parameter(Mandatory)][hashtable]$Context
    )

    switch ($Condition) {
        'always' { return $true }
        'provisioningHost' {
            return Test-WinMintFirstLogonUsesProvisioningHost -AgentMode ([string]$Context.AgentMode)
        }
        'agent-script-staged' { return [bool]$Context.AgentScriptStaged }
        'agentExitCode == 0' { return ([int]$Context.AgentExitCode -eq 0) }
        'agentExitCode != 0' { return ([int]$Context.AgentExitCode -ne 0) }
        'agentExitCode == 0 && !agentNeedsReboot' {
            return ([int]$Context.AgentExitCode -eq 0) -and -not [bool]$Context.AgentNeedsReboot
        }
        'agentExitCode == 0 && agentNeedsReboot' {
            return ([int]$Context.AgentExitCode -eq 0) -and [bool]$Context.AgentNeedsReboot
        }
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
        [Parameter(Mandatory)][ValidateSet('Auto','UI','Console','Headless','SetupShell')]
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
        $mode = Resolve-WinMintFirstLogonAgentMode -RequestedMode $AgentMode
        "$(Get-Date -Format 'o') Launching WinMintAgent in $mode mode (requested=$AgentMode)" | Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
        if ($mode -eq 'Normal') {
            $agentProcess = Start-Process -FilePath $exe -ArgumentList @(
                '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', "`"$AgentPath`""
            ) -WindowStyle Hidden -PassThru
            while (-not $agentProcess.HasExited) {
                Invoke-WinMintSetupShellStatusPumpTick
                Start-Sleep -Milliseconds 250
            }
            $agentExitCode = [int]$agentProcess.ExitCode
        }
        elseif ($AgentMode -eq 'Console' -or [string]$env:WINMINT_FIRSTLOGON_MODE -match '^(console|terminal)$') {
            "$(Get-Date -Format 'o') Waiting for Windows Terminal before launching WinMintAgent." | Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
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

function Resolve-WinMintProvisioningReleasePhase {
    param(
        [Parameter(Mandatory)][hashtable]$Context
    )

    if ([bool]$Context.AgentNeedsReboot) { return 'reboot' }
    if ([int]$Context.AgentExitCode -ne 0) { return 'failed' }
    return 'complete'
}
