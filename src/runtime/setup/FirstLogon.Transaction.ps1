#Requires -Version 5.1

function New-WinMintFirstLogonTransactionStep {
    param(
        [Parameter(Mandatory)][int]$Order,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$Description,
        [string[]]$Functions = @(),
        [ValidateSet('blocking', 'bestEffort', 'conditional')][string]$FailurePolicy = 'bestEffort',
        [string]$Condition = 'always'
    )

    [pscustomobject]@{
        Order = $Order
        Id = $Id
        Phase = $Phase
        Description = $Description
        Functions = @($Functions)
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
                -Phase 'prepare' `
                -Description 'Prepare the elevated FirstLogon host and initialize state.' `
                -Functions @('Set-WinMintFirstLogonWindowsTerminalDefault', 'New-WinMintFirstLogonRunState', 'Save-WinMintFirstLogonState') `
                -FailurePolicy 'bestEffort')) | Out-Null

    $order++
    $steps.Add((New-WinMintFirstLogonTransactionStep `
                -Order $order `
                -Id 'persist-retry-autologon' `
                -Phase 'prepare' `
                -Description 'Persist RunOnce retry and autologon until the agent succeeds.' `
                -Functions @('Set-WinMintFirstLogonRetry', 'Set-WinMintFirstLogonAutoLogonPersistent') `
                -FailurePolicy 'bestEffort')) | Out-Null

    $order++
    $steps.Add((New-WinMintFirstLogonTransactionStep `
                -Order $order `
                -Id 'restore-visible-user-posture' `
                -Phase 'restore' `
                -Description 'Restore the visible user region, locale, time zone, input languages, and location posture before optional work.' `
                -Functions @('Restore-WinMintDmaRegionalDefaults', 'Read-WinMintFirstLogonSetupProfile', 'Set-WinMintFirstLogonInputLanguages') `
                -FailurePolicy 'bestEffort')) | Out-Null

    $order++
    $steps.Add((New-WinMintFirstLogonTransactionStep `
                -Order $order `
                -Id 'apply-live-user-defaults' `
                -Phase 'customize' `
                -Description 'Apply live-user folders, XDG defaults, clipboard, quiet UX, desktop, cursor, AppX cleanup, and OneDrive cleanup.' `
                -Functions @(
                    'Repair-WinMintFirstLogonKnownFolders',
                    'Set-WinMintFirstLogonXdgDefaults',
                    'Set-WinMintFirstLogonClipboardDefaults',
                    'Set-WinMintFirstLogonQuietUxDefaults',
                    'Set-WinMintFirstLogonDesktopDefaults',
                    'Set-WinMintFirstLogonCursorScheme',
                    'Invoke-WinMintFirstLogonAppxCleanup',
                    'Invoke-WinMintFirstLogonOneDriveRemoval'
                ) `
                -FailurePolicy 'bestEffort')) | Out-Null

    $order++
    $steps.Add((New-WinMintFirstLogonTransactionStep `
                -Order $order `
                -Id 'launch-agent' `
                -Phase 'agent' `
                -Description 'Launch the WinMint first-logon agent and capture its exit code.' `
                -Functions @('Resolve-WinMintPowerShellHost', 'Resolve-WinMintFirstLogonAgentMode', 'Start-WinMintFirstLogonAgentInTerminal', 'Start-Process') `
                -FailurePolicy 'blocking')) | Out-Null

    $order++
    $steps.Add((New-WinMintFirstLogonTransactionStep `
                -Order $order `
                -Id 'finalize-user-shell' `
                -Phase 'finalize' `
                -Description 'Finalize terminal profiles and Start pins after the agent has run.' `
                -Functions @('Set-WinMintFirstLogonTerminalProfiles', 'Set-WinMintFirstLogonStartPins') `
                -FailurePolicy 'bestEffort' `
                -Condition 'agent-script-staged')) | Out-Null

    $order++
    $steps.Add((New-WinMintFirstLogonTransactionStep `
                -Order $order `
                -Id 'finalize-success' `
                -Phase 'finalize' `
                -Description 'Clear retry/autologon state and schedule residual payload cleanup after a successful agent exit.' `
                -Functions @('Clear-WinMintFirstLogonRetry', 'Disable-WinMintAutoAdminLogon', 'Clear-WinMintAutoLogonPassword', 'Remove-WinMintResidualPayload') `
                -FailurePolicy 'conditional' `
                -Condition 'agentExitCode == 0')) | Out-Null

    $order++
    $steps.Add((New-WinMintFirstLogonTransactionStep `
                -Order $order `
                -Id 'finalize-recovery' `
                -Phase 'recovery' `
                -Description 'Retain or clear bounded recovery state after an incomplete agent run.' `
                -Functions @('Clear-WinMintFirstLogonRecovery', 'Save-WinMintFirstLogonState') `
                -FailurePolicy 'conditional' `
                -Condition 'agentExitCode != 0')) | Out-Null

    return @($steps)
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
