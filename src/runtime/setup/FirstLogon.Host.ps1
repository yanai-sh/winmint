#Requires -Version 5.1

function Resolve-WinMintPowerShellHost {
    Resolve-WinMintPowerShell7Host
}


function Test-WinMintTokenElevated {
    Test-WinMintProcessElevated
}


function Resolve-WinMintWindowsTerminalHost {
    $wtCommand = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($wtCommand -and -not [string]::IsNullOrWhiteSpace([string]$wtCommand.Source)) {
        return [string]$wtCommand.Source
    }

    $windowsApps = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
    if (Test-Path -LiteralPath $windowsApps) { return $windowsApps }

    $machineAlias = Join-Path $env:ProgramFiles 'WindowsApps\wt.exe'
    if (Test-Path -LiteralPath $machineAlias) { return $machineAlias }

    return ''
}


function Wait-WinMintWindowsTerminalHost {
    param(
        [int]$TimeoutSeconds = 120
    )

    $deadline = (Get-Date).AddSeconds([Math]::Max(0, $TimeoutSeconds))
    do {
        $terminal = Resolve-WinMintWindowsTerminalHost
        if (-not [string]::IsNullOrWhiteSpace($terminal)) {
            return $terminal
        }
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)

    return ''
}


function Start-WinMintFirstLogonAgentInTerminal {
    param(
        [Parameter(Mandatory)][string]$TerminalPath,
        [Parameter(Mandatory)][string]$PowerShellPath,
        [Parameter(Mandatory)][string]$AgentPath
    )

    $ctx = Get-WinMintFirstLogonContext
    $exitCodePath = Join-Path $ctx.LogDir 'WinMintAgent.exitcode'
    $launcherPath = Join-Path $ctx.LogDir 'Start-WinMintAgent.TerminalLauncher.ps1'
    $errorLogPath = Join-Path $ctx.LogDir 'FirstLogon_errors.log'
    Remove-Item -LiteralPath $exitCodePath -Force -ErrorAction SilentlyContinue

    $launcher = @"
`$ErrorActionPreference = 'Continue'
`$exitCode = 1
try {
    & '$AgentPath' -InteractiveFirstLogon
    if (`$null -ne `$global:LASTEXITCODE) {
        `$exitCode = [int]`$global:LASTEXITCODE
    }
    elseif (`$?) {
        `$exitCode = 0
    }
}
catch {
    try {
        "WinMintAgent terminal launcher failed: `$(`$_.Exception.Message)" | Out-File -LiteralPath '$errorLogPath' -Append -Encoding utf8
    }
    catch { }
    `$exitCode = 1
}
try { Set-Content -LiteralPath '$exitCodePath' -Value ([string]`$exitCode) -Encoding ASCII } catch { }
exit `$exitCode
"@
    Set-Content -LiteralPath $launcherPath -Value $launcher -Encoding UTF8

    $wtArguments = @(
        'new-tab',
        '--title', '"WinMint FirstLogon"',
        "`"$PowerShellPath`"",
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$launcherPath`""
    ) -join ' '

    "$(Get-Date -Format 'o') Launching WinMintAgent in Windows Terminal: $TerminalPath $wtArguments" |
        Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log') -Append

    $null = Start-Process -FilePath $TerminalPath -ArgumentList $wtArguments -PassThru
    $deadline = (Get-Date).AddHours(8)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $exitCodePath -PathType Leaf) {
            $rawExitCode = (Get-Content -LiteralPath $exitCodePath -Raw -ErrorAction SilentlyContinue).Trim()
            $parsedExitCode = 1
            if ([int]::TryParse($rawExitCode, [ref]$parsedExitCode)) {
                return $parsedExitCode
            }
            return 1
        }
        Start-Sleep -Seconds 5
    }

    Write-WinMintFirstLogonError 'Timed out waiting for WinMintAgent terminal launcher to report an exit code.'
    return 1
}


function Resolve-WinMintFirstLogonAgentMode {
    param(
        [Parameter(Mandatory)][string]$RequestedMode
    )

    if ([string]$env:WINMINT_FIRSTLOGON_DEBUG -eq '1') { return 'Debug' }

    $envMode = [string]$env:WINMINT_FIRSTLOGON_MODE
    if (-not [string]::IsNullOrWhiteSpace($envMode)) {
        switch -Regex ($envMode.Trim()) {
            '^(headless|none|no-ui|console|terminal|debug)$' { return 'Debug' }
        }
    }

    if ($RequestedMode -in @('Console', 'Headless')) { return 'Debug' }
    # Auto, UI, and SetupShell map to Normal (fullscreen provisioning shell + hidden agent).
    return 'Normal'
}


function Stop-WinMintFirstLogonUnelevated {
    param([Parameter(Mandatory)][string]$Reason)

    Write-WinMintFirstLogonError $Reason
    Remove-Item -LiteralPath (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon_self-elevation.flag') -Force -ErrorAction SilentlyContinue
    $state = New-WinMintFirstLogonRunState
    $state['status'] = 'failed'
    $state['failure'] = 'notElevated'
    $state['error'] = $Reason
    try {
        Save-WinMintFirstLogonState -State $state
    }
    catch { Write-WinMintFirstLogonError "FirstLogon state write failed: $_" }
    if ([int]$state.attempts -ge (Get-WinMintFirstLogonContext).MaxAttempts) {
        Write-WinMintFirstLogonError "FirstLogon retry cap reached ($($state.attempts)); clearing autologon recovery state."
        Clear-WinMintFirstLogonRecovery
    }
    else {
        try { Set-WinMintFirstLogonRetry } catch { Write-WinMintFirstLogonError "FirstLogon retry registration failed: $_" }
        try { Set-WinMintFirstLogonAutoLogonPersistent } catch { Write-WinMintFirstLogonError "AutoLogon persistence failed: $_" }
    }
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
    exit 1
}

function Test-WinMintFirstLogonUsesProvisioningHost {
    param(
        [Parameter(Mandatory)][string]$AgentMode
    )

    return (Resolve-WinMintFirstLogonAgentMode -RequestedMode $AgentMode) -eq 'Normal'
}


function Invoke-WinMintFirstLogonBootstrapSession {
    # Elevation + pwsh7 relaunch collapsed into one named transaction step.
    $ctx = Get-WinMintFirstLogonContext
    $logPath = Join-Path $ctx.LogDir 'FirstLogon.log'

    $elevated = $false
    try { $elevated = Test-WinMintTokenElevated }
    catch { $elevated = $false }
    Set-WinMintFirstLogonContextElevated -Elevated $elevated
    "$(Get-Date -Format 'o') FirstLogon running elevated: $elevated" | Out-File -LiteralPath $logPath -Append

    if (-not $elevated) {
        $elevFlag = Join-Path $ctx.LogDir 'FirstLogon_self-elevation.flag'
        if (Test-Path -LiteralPath $elevFlag) {
            Stop-WinMintFirstLogonUnelevated -Reason 'FirstLogon is NOT elevated and self-elevation was already attempted; aborting before machine-wide setup so RunOnce can retry.'
        }
        try {
            Set-Content -LiteralPath $elevFlag -Value (Get-Date -Format o) -Encoding ASCII
            $exe = Resolve-WinMintPowerShellHost
            $taskName = 'WinMintFirstLogonElevated'
            $entryPath = $ctx.EntryPath
            $tr = "`"$exe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$entryPath`""
            & schtasks.exe /Create /TN $taskName /TR $tr /SC ONCE /ST 23:59 /RL HIGHEST /F 2>&1 | Out-Null
            $elevOk = ($LASTEXITCODE -eq 0)
            if ($elevOk) { & schtasks.exe /Run /TN $taskName 2>&1 | Out-Null; $elevOk = ($LASTEXITCODE -eq 0) }
            if ($elevOk) {
                "$(Get-Date -Format 'o') FirstLogon re-launched elevated via scheduled task '$taskName'; standard-token instance exiting." |
                    Out-File -LiteralPath $logPath -Append
                try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
                return @{ ShouldExit = $true; ExitCode = 0 }
            }
            Stop-WinMintFirstLogonUnelevated -Reason 'Self-elevation scheduled task could not be created/started; aborting before machine-wide setup so RunOnce can retry.'
        }
        catch { Stop-WinMintFirstLogonUnelevated -Reason "Self-elevation failed: $_; aborting before machine-wide setup so RunOnce can retry." }
    }

    if ($elevated -and $PSVersionTable.PSVersion.Major -lt 7) {
        $pwsh7 = Resolve-WinMintPowerShellHost
        $p7Flag = Join-Path $ctx.LogDir 'FirstLogon_pwsh7.flag'
        if (-not (Test-Path -LiteralPath $pwsh7 -PathType Leaf)) {
            Write-WinMintFirstLogonError "PowerShell 7 is required for FirstLogon but was not found: $pwsh7"
            return @{ ShouldExit = $true; ExitCode = 1 }
        }
        if (-not (Test-Path -LiteralPath $p7Flag)) {
            try {
                Set-Content -LiteralPath $p7Flag -Value (Get-Date -Format o) -Encoding ASCII
                "$(Get-Date -Format 'o') Re-launching FirstLogon under PowerShell 7 ($pwsh7); the 5.1 instance waits for it." | Out-File -LiteralPath $logPath -Append
                try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
                $p7 = Start-Process -FilePath $pwsh7 -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$($ctx.EntryPath)`"") -Wait -PassThru
                return @{ ShouldExit = $true; ExitCode = ([int]$p7.ExitCode) }
            }
            catch {
                Write-WinMintFirstLogonError "PowerShell 7 re-launch failed: $_"
                try { Start-Transcript -Path (Join-Path $ctx.LogDir 'FirstLogon_transcript.log') -Append -ErrorAction SilentlyContinue | Out-Null } catch { }
                return @{ ShouldExit = $true; ExitCode = 1 }
            }
        }
    }

    "$(Get-Date -Format 'o') FirstLogon host: PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))" | Out-File -LiteralPath $logPath -Append
    return @{ ShouldExit = $false; ExitCode = 0 }
}
