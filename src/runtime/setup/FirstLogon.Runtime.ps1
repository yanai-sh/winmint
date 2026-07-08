#Requires -Version 5.1

function Invoke-WinMintFirstLogonBestEffort {
    param(
        [Parameter(Mandatory)][string]$ErrorMessage,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )

    try {
        & $ScriptBlock
    }
    catch {
        Write-WinMintFirstLogonError "$ErrorMessage`: $_"
    }
}

function Invoke-WinMintFirstLogonSetupPhase {
    [CmdletBinding()]
    param(
        [ValidateSet('Auto','UI','Console','Headless','SetupShell')]
        [string]$AgentMode = 'Auto'
    )

    $ctx = Get-WinMintFirstLogonContext
    $agentRoot = Join-Path $ctx.PayloadDir 'WinMintAgent'
    $agent = Join-Path $agentRoot 'Start-WinMintAgent.ps1'
    $context = @{
        AgentMode = $AgentMode
        AgentRoot = $agentRoot
        AgentPath = $agent
        AgentScriptStaged = (Test-Path -LiteralPath $agent)
        AgentExitCode = 1
        AgentNeedsReboot = $false
        State = $null
        SetupShellProcess = $null
        EarlyExit = $null
    }

    $transactionPlan = @(New-WinMintFirstLogonTransactionPlan -AgentMode $AgentMode)
    $transactionAdapters = @{
        'bootstrap-session' = {
            param([hashtable]$Context, $Step)
            [void]$Step
            $boot = Invoke-WinMintFirstLogonBootstrapSession
            if ($boot.ShouldExit) {
                $Context.EarlyExit = [int]$boot.ExitCode
            }
        }
        'prepare-host' = {
            param([hashtable]$Context, $Step)
            [void]$Step
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Windows Terminal delegation clear failed' -ScriptBlock { Clear-WinMintFirstLogonWindowsTerminalDelegation }
            $Context.State = New-WinMintFirstLogonRunState
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'FirstLogon state write failed' -ScriptBlock { Save-WinMintFirstLogonState -State $Context.State }
        }
        'persist-retry-autologon' = {
            param([hashtable]$Context, $Step)
            [void]$Context
            [void]$Step
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'FirstLogon retry registration failed' -ScriptBlock { Set-WinMintFirstLogonRetry }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'AutoLogon persistence failed' -ScriptBlock { Set-WinMintFirstLogonAutoLogonPersistent }
        }
        'engage-provisioning-lock' = {
            param([hashtable]$Context, $Step)
            [void]$Step
            $shellRoot = Get-WinMintSetupShellRoot
            Set-WinMintSetupShellControl -Phase 'running' -ProfileName (Get-WinMintSetupShellProfileName) -PreAgentStage 'locked'
            Update-WinMintSetupShellStatus -ShellRoot $shellRoot -PreAgentStage 'locked' | Out-Null
            Enable-WinMintProvisioningGuard
            Start-WinMintSetupShellStatusPump | Out-Null
            $Context.SetupShellProcess = Start-WinMintProvisioningHost
        }
        'restore-visible-user-posture' = {
            param([hashtable]$Context, $Step)
            [void]$Step
            if ($Context.SetupShellProcess) {
                Update-WinMintSetupShellStatus -PreAgentStage 'region' | Out-Null
            }
            $dmaRestore = Restore-WinMintDmaRegionalDefaults
            if ($dmaRestore.Enabled -and -not $dmaRestore.Compliant) {
                $Context.State['dmaRestore'] = 'noncompliant'
                $Context.State['dmaRestoreReport'] = $dmaRestore.Report
                $Context.State['dmaRestoreErrors'] = @($dmaRestore.Errors)
                Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'FirstLogon state write failed' -ScriptBlock { Save-WinMintFirstLogonState -State $Context.State }
                Write-WinMintFirstLogonError "DMA regional restore reported non-compliant; continuing with personalization and agent. Report: $($dmaRestore.Report); Errors: $(@($dmaRestore.Errors) -join ' | ')"
            }

            if (-not $dmaRestore.Enabled) {
                Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Secondary input language setup (non-DMA) failed' -ScriptBlock {
                    $flSetupProfile = Read-WinMintFirstLogonSetupProfile
                    $flSecondaryInputLanguages = @()
                    if ($flSetupProfile -and $flSetupProfile.PSObject.Properties['regional'] -and $flSetupProfile.regional.PSObject.Properties['secondaryInputLanguages']) {
                        $flSecondaryInputLanguages = @($flSetupProfile.regional.secondaryInputLanguages)
                    }
                    if (@($flSecondaryInputLanguages).Count -gt 0) {
                        Set-WinMintFirstLogonInputLanguages -DisplayLanguage 'en-US' -SecondaryInputLanguages $flSecondaryInputLanguages
                    }
                }
            }
        }
        'apply-live-user-defaults' = {
            param([hashtable]$Context, $Step)
            [void]$Step
            if ($Context.SetupShellProcess) {
                Update-WinMintSetupShellStatus -PreAgentStage 'defaults' | Out-Null
            }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Known folder repair failed' -ScriptBlock { Repair-WinMintFirstLogonKnownFolders }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'XDG defaults failed' -ScriptBlock { Set-WinMintFirstLogonXdgDefaults }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Clipboard defaults failed' -ScriptBlock { Set-WinMintFirstLogonClipboardDefaults }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Quiet UX defaults failed' -ScriptBlock { Set-WinMintFirstLogonQuietUxDefaults }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Desktop defaults failed' -ScriptBlock { Set-WinMintFirstLogonDesktopDefaults }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Cursor scheme apply failed' -ScriptBlock { Set-WinMintFirstLogonCursorScheme }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Live AppX cleanup failed' -ScriptBlock { Invoke-WinMintFirstLogonAppxCleanup }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'OneDrive user cleanup failed' -ScriptBlock { Invoke-WinMintFirstLogonOneDriveRemoval }
        }
        'run-agent' = {
            param([hashtable]$Context, $Step)
            [void]$Step
            if ($Context.SetupShellProcess) {
                Update-WinMintSetupShellStatus -PreAgentStage 'agent' | Out-Null
            }
            $Context.AgentExitCode = Invoke-WinMintFirstLogonAgentLaunch -AgentMode ([string]$Context.AgentMode) -AgentRoot ([string]$Context.AgentRoot) -AgentPath ([string]$Context.AgentPath)
            $Context.AgentNeedsReboot = Test-WinMintFirstLogonAgentNeedsReboot
            $Context.State['agentExitCode'] = $Context.AgentExitCode
            $Context.State['completedAt'] = Get-Date -Format o
        }
        'finalize-desktop-under-lock' = {
            param([hashtable]$Context, $Step)
            [void]$Step
            if ($Context.SetupShellProcess) {
                $paths = Get-WinMintSetupShellLocalPaths
                $agentState = Read-WinMintSetupShellJson -Path $paths.AgentStatePath
                $progress = Get-WinMintSetupShellAgentProgress -AgentState $agentState
                $finishMessage = if ($progress.WarningCount -gt 0) {
                    'Setup completed with optional items skipped.'
                }
                else { '' }
                $shellPhase = if ($Context.AgentNeedsReboot) { 'reboot' } else { 'finishing' }
                Set-WinMintSetupShellControl -Phase $shellPhase -ProfileName (Get-WinMintSetupShellProfileName) -Message $finishMessage
                Update-WinMintSetupShellStatus | Out-Null
            }
            $agentProfilePath = Join-Path ([string]$Context.AgentRoot) 'WinMintAgentProfile.json'
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Windows Terminal default-host setup failed' -ScriptBlock { Set-WinMintFirstLogonWindowsTerminalDefault }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Windows Terminal profile finalization failed' -ScriptBlock { Set-WinMintFirstLogonTerminalProfiles -AgentProfilePath $agentProfilePath }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Start pins apply failed' -ScriptBlock { Set-WinMintFirstLogonStartPins -AgentProfilePath $agentProfilePath }
        }
        'release-provisioning-lock' = {
            param([hashtable]$Context, $Step)
            [void]$Step
            if (-not $Context.SetupShellProcess) { return }
            $releasePhase = Resolve-WinMintProvisioningReleasePhase -Context $Context
            if ($releasePhase -eq 'complete' -and (Test-WinMintSetupRetainFirstLogonArtifacts)) {
                Start-Sleep -Seconds 10
            }
            Set-WinMintSetupShellControl -Phase $releasePhase -ProfileName (Get-WinMintSetupShellProfileName)
            Update-WinMintSetupShellStatus | Out-Null
            Wait-WinMintProvisioningHost -Process $Context.SetupShellProcess -TimeoutSeconds 120
            $Context.SetupShellProcess = $null
        }
        'finalize-reboot-resume' = {
            param([hashtable]$Context, $Step)
            [void]$Step
            $Context.State['status'] = 'rebootPending'
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'FirstLogon retry registration failed' -ScriptBlock { Set-WinMintFirstLogonRetry }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'AutoLogon persistence failed' -ScriptBlock { Set-WinMintFirstLogonAutoLogonPersistent }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Post-agent reboot schedule failed' -ScriptBlock {
                Write-WinMintFirstLogonError 'Agent reported needsReboot; scheduling restart to resume first logon.'
                & shutdown.exe /r /t 60 /c 'WinMint setup will restart to continue first logon.'
            }
        }
        'finalize-success' = {
            param([hashtable]$Context, $Step)
            [void]$Step
            $Context.State['status'] = 'ok'
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'AutoLogon cleanup failed' -ScriptBlock {
                Clear-WinMintFirstLogonRetry
                Invoke-WinMintFirstLogonReg -Arguments @('delete', 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce', '/v', 'WinMintFirstLogon', '/f') -AllowFailure
                Disable-WinMintAutoAdminLogon
                Clear-WinMintAutoLogonPassword
                & schtasks.exe /Delete /TN 'WinMintFirstLogonElevated' /F 2>&1 | Out-Null
                Remove-Item -LiteralPath (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon_self-elevation.flag') -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon_pwsh7.flag') -Force -ErrorAction SilentlyContinue
            }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Residual cleanup failed' -ScriptBlock { Remove-WinMintResidualPayload }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Explorer reload for Start pins failed' -ScriptBlock { Invoke-WinMintFirstLogonReloadExplorerShell }
        }
        'finalize-recovery' = {
            param([hashtable]$Context, $Step)
            [void]$Step
            $Context.State['status'] = 'failed'
            if ([int]$Context.State.attempts -ge (Get-WinMintFirstLogonContext).MaxAttempts) {
                $Context.State['recovery'] = 'exhausted'
                Write-WinMintFirstLogonError "Agent run incomplete after $($Context.State.attempts) attempt(s); clearing autologon recovery state."
                Clear-WinMintFirstLogonRecovery
            }
            else {
                Write-WinMintFirstLogonError 'Agent run incomplete: persistent autologon and the password are left in place so the next reboot signs in automatically and RunOnce retries FirstLogon without prompting.'
            }
        }
    }

    Invoke-WinMintFirstLogonTransactionPlan -Plan $transactionPlan -Context $context -StepAdapters $transactionAdapters | Out-Null

    if ($null -ne $context.EarlyExit) {
        try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
        return [int]$context.EarlyExit
    }

    $state = $context.State
    $agentExitCode = [int]$context.AgentExitCode
    Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'FirstLogon state write failed' -ScriptBlock { Save-WinMintFirstLogonState -State $state }
    "$(Get-Date -Format 'o') FirstLogon.ps1 end" | Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
    if ($agentExitCode -ne 0) { return $agentExitCode }
    return 0
}
