#Requires -Version 5.1

function Invoke-WinMintFirstLogonSetupPhase {
    [CmdletBinding()]
    param(
        [ValidateSet('Auto','UI','Console','Headless')]
        [string]$AgentMode = 'Auto'
    )

    # Prefer PowerShell 7 (the agent + modern tooling expect it). The not-elevated path above
    # already re-launches under pwsh 7 (Resolve-WinMintPowerShellHost). If we are elevated but
    # under Windows PowerShell 5.1, re-launch IN-PLACE under pwsh 7 - Start-Process inherits the
    # current (already elevated) token. A flag prevents a re-launch loop, and the International
    # cmdlets the DMA restore needs are available under pwsh 7.
    if ($script:WinMintElevated -and $PSVersionTable.PSVersion.Major -lt 7) {
        $pwsh7 = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
        $p7Flag = Join-Path $logDir 'FirstLogon_pwsh7.flag'
        if ((Test-Path -LiteralPath $pwsh7) -and -not (Test-Path -LiteralPath $p7Flag)) {
            try {
                Set-Content -LiteralPath $p7Flag -Value (Get-Date -Format o) -Encoding ASCII
                "$(Get-Date -Format 'o') Re-launching FirstLogon under PowerShell 7 ($pwsh7); the 5.1 instance waits for it." | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
                try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
                $p7 = Start-Process -FilePath $pwsh7 -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$script:WinMintFirstLogonEntryPath`"") -Wait -PassThru
                return ([int]$p7.ExitCode)
            }
            catch {
                Write-WinMintFirstLogonError "pwsh 7 re-launch failed: $_; continuing under Windows PowerShell $($PSVersionTable.PSVersion)."
                try { Start-Transcript -Path (Join-Path $logDir 'FirstLogon_transcript.log') -Append -ErrorAction SilentlyContinue | Out-Null } catch { }
            }
        }
    }
    "$(Get-Date -Format 'o') FirstLogon host: PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
    try { Set-WinMintFirstLogonWindowsTerminalDefault } catch { Write-WinMintFirstLogonError "Windows Terminal default-host setup failed: $_" }

    $state = New-WinMintFirstLogonRunState
    try { Save-WinMintFirstLogonState -State $state } catch { Write-WinMintFirstLogonError "FirstLogon state write failed: $_" }
    try { Set-WinMintFirstLogonRetry } catch { Write-WinMintFirstLogonError "FirstLogon retry registration failed: $_" }
    # Keep auto sign-in alive across every install reboot until the agent completes. The
    # agent can reboot mid-run; clearing the autologon password now would force a password
    # prompt on the next boot. Make autologon persistent here and only disable it + wipe the
    # password once the agent run succeeds (below). The plaintext password therefore stays
    # in the registry for the duration of the unattended install - an intentional, bounded
    # trade for a fully hands-off setup (cleared the moment the agent reports success).
    try { Set-WinMintFirstLogonAutoLogonPersistent } catch { Write-WinMintFirstLogonError "AutoLogon persistence failed: $_" }

    $dmaRestore = Restore-WinMintDmaRegionalDefaults
    if ($dmaRestore.Enabled -and -not $dmaRestore.Compliant) {
        # Regional restore is best-effort and self-verifying; a compliance miss (e.g. a
        # post-restore read that has not yet propagated) must NOT abort the rest of
        # FirstLogon - doing so left the desktop fully vanilla (no theme/wallpaper/agent).
        # Record it loudly and continue with personalization and the agent. RunOnce still
        # re-runs FirstLogon on the next logon to re-attempt the regional restore.
        $state['dmaRestore'] = 'noncompliant'
        $state['dmaRestoreReport'] = $dmaRestore.Report
        $state['dmaRestoreErrors'] = @($dmaRestore.Errors)
        try { Save-WinMintFirstLogonState -State $state } catch { Write-WinMintFirstLogonError "FirstLogon state write failed: $_" }
        Write-WinMintFirstLogonError "DMA regional restore reported non-compliant; continuing with personalization and agent. Report: $($dmaRestore.Report); Errors: $(@($dmaRestore.Errors) -join ' | ')"
    }

    # When DMA interop is OFF, Restore-WinMintDmaRegionalDefaults does not touch the language list,
    # so add any configured secondary input languages (keyboards) here. (When DMA is ON, the
    # restore already rebuilt the list with these.) Display stays en-US.
    if (-not $dmaRestore.Enabled) {
        try {
            $flSetupProfile = Read-WinMintFirstLogonSetupProfile
            $flSecondaryInputLanguages = @()
            if ($flSetupProfile -and $flSetupProfile.PSObject.Properties['regional'] -and $flSetupProfile.regional.PSObject.Properties['secondaryInputLanguages']) {
                $flSecondaryInputLanguages = @($flSetupProfile.regional.secondaryInputLanguages)
            }
            if (@($flSecondaryInputLanguages).Count -gt 0) {
                Set-WinMintFirstLogonInputLanguages -DisplayLanguage 'en-US' -SecondaryInputLanguages $flSecondaryInputLanguages
            }
        }
        catch { Write-WinMintFirstLogonError "Secondary input language setup (non-DMA) failed: $_" }
    }

    try { Repair-WinMintFirstLogonKnownFolders } catch { Write-WinMintFirstLogonError "Known folder repair failed: $_" }
    try { Set-WinMintFirstLogonXdgDefaults } catch { Write-WinMintFirstLogonError "XDG defaults failed: $_" }
    try { Set-WinMintFirstLogonClipboardDefaults } catch { Write-WinMintFirstLogonError "Clipboard defaults failed: $_" }
    try { Set-WinMintFirstLogonQuietUxDefaults } catch { Write-WinMintFirstLogonError "Quiet UX defaults failed: $_" }
    try { Set-WinMintFirstLogonDesktopDefaults } catch { Write-WinMintFirstLogonError "Desktop defaults failed: $_" }
    try { Set-WinMintFirstLogonCursorScheme } catch { Write-WinMintFirstLogonError "Cursor scheme apply failed: $_" }
    try { Invoke-WinMintFirstLogonAppxCleanup } catch { Write-WinMintFirstLogonError "Live AppX cleanup failed: $_" }
    try { Invoke-WinMintFirstLogonOneDriveRemoval } catch { Write-WinMintFirstLogonError "OneDrive user cleanup failed: $_" }

    $agentExitCode = 0
    $agentRoot = Join-Path $payloadDir 'WinMintAgent'
    $agent     = Join-Path $agentRoot 'Start-WinMintAgent.ps1'
    if (Test-Path -LiteralPath $agent) {
        try {
            $exe = Resolve-WinMintPowerShellHost
            # The agent is the source of truth and does all first-logon work. Default is a
            # visible console so the user can see progress while the automation runs.
            $mode = Resolve-WinMintFirstLogonAgentMode -RequestedMode $AgentMode
            "$(Get-Date -Format 'o') Launching WinMintAgent in $mode mode" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
            if ($mode -eq 'Console') {
                $agentProcess = Start-Process -FilePath $exe -ArgumentList @(
                    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                    '-File', "`"$agent`"", '-InteractiveFirstLogon'
                ) -WindowStyle Normal -Wait -PassThru
                $agentExitCode = [int]$agentProcess.ExitCode
            }
            else {
                # Headless mode stays available for automation, but it is opt-in now.
                $agentProcess = Start-Process -FilePath $exe -ArgumentList @(
                    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                    '-File', "`"$agent`""
                ) -WindowStyle Hidden -Wait -PassThru
                $agentExitCode = [int]$agentProcess.ExitCode
            }
            if ($agentExitCode -ne 0) { Write-WinMintFirstLogonError "WinMintAgent exited with code $agentExitCode" }
        }
        catch {
            $agentExitCode = 1
            Write-WinMintFirstLogonError "WinMintAgent launch failed: $_"
        }
    }
    else {
        $agentExitCode = 1
        Write-WinMintFirstLogonError "WinMintAgent script was not found: $agent"
    }

    $state['agentExitCode'] = $agentExitCode
    $state['completedAt'] = Get-Date -Format o
    if (Test-Path -LiteralPath $agent) {
        try { Set-WinMintFirstLogonTerminalProfiles -AgentProfilePath (Join-Path $agentRoot 'BuildProfile.json') }
        catch { Write-WinMintFirstLogonError "Windows Terminal profile finalization failed: $_" }
        try { Set-WinMintFirstLogonStartPins -AgentProfilePath (Join-Path $agentRoot 'BuildProfile.json') }
        catch { Write-WinMintFirstLogonError "Start pins apply failed: $_" }
    }

    # The agent run is the source of truth. A pending-reboot flag here is the always-set CBS
    # servicing artifact, NOT a real "must reboot" - and a post-agent reboot is exactly what
    # broke autologon: it landed the next logon on a password prompt. So on success we DO NOT
    # reboot - tear down autologon + the password and finish on the desktop. Any reboot a
    # module genuinely needs is handled inside the agent's own run (it persists autologon and
    # resumes via the RunOnce retry).
    if ($agentExitCode -eq 0) {
        # Install complete: stop the retry, disable autologon, and wipe the password.
        $state['status'] = 'ok'
        try {
            Clear-WinMintFirstLogonRetry
            Invoke-WinMintFirstLogonReg -Arguments @('delete', 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce', '/v', 'WinMintFirstLogon', '/f') -AllowFailure
            Disable-WinMintAutoAdminLogon
            Clear-WinMintAutoLogonPassword
            # Remove the self-elevation / pwsh7 re-launch scaffolding now that setup is complete.
            & schtasks.exe /Delete /TN 'WinMintFirstLogonElevated' /F 2>&1 | Out-Null
            Remove-Item -LiteralPath (Join-Path $logDir 'FirstLogon_self-elevation.flag') -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path $logDir 'FirstLogon_pwsh7.flag') -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-WinMintFirstLogonError "AutoLogon cleanup failed: $_"
        }
        try { Remove-WinMintResidualPayload }
        catch { Write-WinMintFirstLogonError "Residual cleanup failed: $_" }
    }
    else {
        $state['status'] = 'failed'
        if ([int]$state.attempts -ge $script:WinMintFirstLogonMaxAttempts) {
            $state['recovery'] = 'exhausted'
            Write-WinMintFirstLogonError "Agent run incomplete after $($state.attempts) attempt(s); clearing autologon recovery state."
            Clear-WinMintFirstLogonRecovery
        }
        else {
            Write-WinMintFirstLogonError 'Agent run incomplete: persistent autologon and the password are left in place so the next reboot signs in automatically and RunOnce retries FirstLogon without prompting.'
        }
    }
    try { Save-WinMintFirstLogonState -State $state } catch { Write-WinMintFirstLogonError "FirstLogon state write failed: $_" }
    "$(Get-Date -Format 'o') FirstLogon.ps1 end" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
    if ($agentExitCode -ne 0) { return $agentExitCode }
    return 0
}
