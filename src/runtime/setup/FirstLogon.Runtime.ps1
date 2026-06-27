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
        [ValidateSet('Auto','UI','Console','Headless')]
        [string]$AgentMode = 'Auto'
    )

    # PowerShell 7 is bundled into the image and is required for WinMint setup work. If this
    # elevated instance is still under Windows PowerShell 5.1, re-launch in-place under pwsh 7;
    # Start-Process inherits the current elevated token. A flag prevents a re-launch loop.
    if ((Get-WinMintFirstLogonContext).Elevated -and $PSVersionTable.PSVersion.Major -lt 7) {
        $pwsh7 = Resolve-WinMintPowerShellHost
        $p7Flag = Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon_pwsh7.flag'
        if (-not (Test-Path -LiteralPath $pwsh7 -PathType Leaf)) {
            Write-WinMintFirstLogonError "PowerShell 7 is required for FirstLogon but was not found: $pwsh7"
            return 1
        }
        if (-not (Test-Path -LiteralPath $p7Flag)) {
            try {
                Set-Content -LiteralPath $p7Flag -Value (Get-Date -Format o) -Encoding ASCII
                "$(Get-Date -Format 'o') Re-launching FirstLogon under PowerShell 7 ($pwsh7); the 5.1 instance waits for it." | Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
                try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
                $entryPath = (Get-WinMintFirstLogonContext).EntryPath
                $p7 = Start-Process -FilePath $pwsh7 -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$entryPath`"") -Wait -PassThru
                return ([int]$p7.ExitCode)
            }
            catch {
                Write-WinMintFirstLogonError "PowerShell 7 re-launch failed: $_"
                try { Start-Transcript -Path (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon_transcript.log') -Append -ErrorAction SilentlyContinue | Out-Null } catch { }
                return 1
            }
        }
    }
    "$(Get-Date -Format 'o') FirstLogon host: PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))" | Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append

    $ctx = Get-WinMintFirstLogonContext
    $agentRoot = Join-Path $ctx.PayloadDir 'WinMintAgent'
    $agent = Join-Path $agentRoot 'Start-WinMintAgent.ps1'
    $context = @{
        AgentMode = $AgentMode
        AgentRoot = $agentRoot
        AgentPath = $agent
        AgentScriptStaged = (Test-Path -LiteralPath $agent)
        AgentExitCode = 1
        State = $null
    }

    $transactionPlan = @(New-WinMintFirstLogonTransactionPlan -AgentMode $AgentMode)
    $transactionAdapters = @{
        'prepare-host' = {
            param([hashtable]$Context, $Step)
            [void]$Step
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Windows Terminal default-host setup failed' -ScriptBlock { Set-WinMintFirstLogonWindowsTerminalDefault }
            $Context.State = New-WinMintFirstLogonRunState
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'FirstLogon state write failed' -ScriptBlock { Save-WinMintFirstLogonState -State $Context.State }
        }
        'persist-retry-autologon' = {
            param([hashtable]$Context, $Step)
            [void]$Context
            [void]$Step
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'FirstLogon retry registration failed' -ScriptBlock { Set-WinMintFirstLogonRetry }
            # Keep auto sign-in alive across every install reboot until the agent completes. The
            # agent can reboot mid-run; clearing the autologon password now would force a password
            # prompt on the next boot. Make autologon persistent here and only disable it + wipe the
            # password once the agent run succeeds (below). The plaintext password therefore stays
            # in the registry for the duration of the unattended install - an intentional, bounded
            # trade for a fully hands-off setup (cleared the moment the agent reports success).
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'AutoLogon persistence failed' -ScriptBlock { Set-WinMintFirstLogonAutoLogonPersistent }
        }
        'restore-visible-user-posture' = {
            param([hashtable]$Context, $Step)
            [void]$Step
            $dmaRestore = Restore-WinMintDmaRegionalDefaults
            if ($dmaRestore.Enabled -and -not $dmaRestore.Compliant) {
                # Regional restore is best-effort and self-verifying; a compliance miss (e.g. a
                # post-restore read that has not yet propagated) must NOT abort the rest of
                # FirstLogon - doing so left the desktop fully vanilla (no theme/wallpaper/agent).
                # Record it loudly and continue with personalization and the agent. RunOnce still
                # re-runs FirstLogon on the next logon to re-attempt the regional restore.
                $Context.State['dmaRestore'] = 'noncompliant'
                $Context.State['dmaRestoreReport'] = $dmaRestore.Report
                $Context.State['dmaRestoreErrors'] = @($dmaRestore.Errors)
                Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'FirstLogon state write failed' -ScriptBlock { Save-WinMintFirstLogonState -State $Context.State }
                Write-WinMintFirstLogonError "DMA regional restore reported non-compliant; continuing with personalization and agent. Report: $($dmaRestore.Report); Errors: $(@($dmaRestore.Errors) -join ' | ')"
            }

            # When DMA interop is OFF, Restore-WinMintDmaRegionalDefaults does not touch the language list,
            # so add any configured secondary input languages (keyboards) here. (When DMA is ON, the
            # restore already rebuilt the list with these.) Display stays en-US.
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
            [void]$Context
            [void]$Step
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Known folder repair failed' -ScriptBlock { Repair-WinMintFirstLogonKnownFolders }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'XDG defaults failed' -ScriptBlock { Set-WinMintFirstLogonXdgDefaults }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Clipboard defaults failed' -ScriptBlock { Set-WinMintFirstLogonClipboardDefaults }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Quiet UX defaults failed' -ScriptBlock { Set-WinMintFirstLogonQuietUxDefaults }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Desktop defaults failed' -ScriptBlock { Set-WinMintFirstLogonDesktopDefaults }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Cursor scheme apply failed' -ScriptBlock { Set-WinMintFirstLogonCursorScheme }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Live AppX cleanup failed' -ScriptBlock { Invoke-WinMintFirstLogonAppxCleanup }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'OneDrive user cleanup failed' -ScriptBlock { Invoke-WinMintFirstLogonOneDriveRemoval }
        }
        'launch-agent' = {
            param([hashtable]$Context, $Step)
            [void]$Step
            $Context.AgentExitCode = Invoke-WinMintFirstLogonAgentLaunch -AgentMode ([string]$Context.AgentMode) -AgentRoot ([string]$Context.AgentRoot) -AgentPath ([string]$Context.AgentPath)
            $Context.State['agentExitCode'] = $Context.AgentExitCode
            $Context.State['completedAt'] = Get-Date -Format o
        }
        'finalize-user-shell' = {
            param([hashtable]$Context, $Step)
            [void]$Step
            $agentProfilePath = Join-Path ([string]$Context.AgentRoot) 'BuildProfile.json'
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Windows Terminal profile finalization failed' -ScriptBlock { Set-WinMintFirstLogonTerminalProfiles -AgentProfilePath $agentProfilePath }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Start pins apply failed' -ScriptBlock { Set-WinMintFirstLogonStartPins -AgentProfilePath $agentProfilePath }
        }
        'finalize-success' = {
            param([hashtable]$Context, $Step)
            [void]$Step
            # The agent run is the source of truth. A pending-reboot flag here is the always-set CBS
            # servicing artifact, NOT a real "must reboot" - and a post-agent reboot is exactly what
            # broke autologon: it landed the next logon on a password prompt. So on success we DO NOT
            # reboot - tear down autologon + the password and finish on the desktop. Any reboot a
            # module genuinely needs is handled inside the agent's own run (it persists autologon and
            # resumes via the RunOnce retry).
            $Context.State['status'] = 'ok'
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'AutoLogon cleanup failed' -ScriptBlock {
                Clear-WinMintFirstLogonRetry
                Invoke-WinMintFirstLogonReg -Arguments @('delete', 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce', '/v', 'WinMintFirstLogon', '/f') -AllowFailure
                Disable-WinMintAutoAdminLogon
                Clear-WinMintAutoLogonPassword
                # Remove the self-elevation / pwsh7 re-launch scaffolding now that setup is complete.
                & schtasks.exe /Delete /TN 'WinMintFirstLogonElevated' /F 2>&1 | Out-Null
                Remove-Item -LiteralPath (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon_self-elevation.flag') -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon_pwsh7.flag') -Force -ErrorAction SilentlyContinue
            }
            Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'Residual cleanup failed' -ScriptBlock { Remove-WinMintResidualPayload }
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
    $state = $context.State
    $agentExitCode = [int]$context.AgentExitCode
    Invoke-WinMintFirstLogonBestEffort -ErrorMessage 'FirstLogon state write failed' -ScriptBlock { Save-WinMintFirstLogonState -State $state }
    "$(Get-Date -Format 'o') FirstLogon.ps1 end" | Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
    if ($agentExitCode -ne 0) { return $agentExitCode }
    return 0
}
