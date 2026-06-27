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

    $exitCodePath = Join-Path $logDir 'WinMintAgent.exitcode'
    $launcherPath = Join-Path $logDir 'Start-WinMintAgent.TerminalLauncher.ps1'
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
        "WinMintAgent terminal launcher failed: `$(`$_.Exception.Message)" | Out-File -LiteralPath '$logDir\FirstLogon_errors.log' -Append -Encoding utf8
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
        Out-File (Join-Path $logDir 'FirstLogon.log') -Append

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

    $envMode = [string]$env:WINMINT_FIRSTLOGON_MODE
    if (-not [string]::IsNullOrWhiteSpace($envMode)) {
        switch -Regex ($envMode.Trim()) {
            '^(headless|none|no-ui)$' { return 'Headless' }
            '^(console|terminal|ui)$' { return 'Console' }
        }
    }

    if ($RequestedMode -ne 'Auto') {
        if ($RequestedMode -eq 'UI') { return 'Console' }
        return $RequestedMode
    }
    # Default to a visible progress console so the user can see first-logon automation
    # moving while the selected installs and setup work finish. A silent headless run is
    # still available explicitly via -AgentMode Headless / WINMINT_FIRSTLOGON_MODE=headless.
    return 'Console'
}


function Stop-WinMintFirstLogonUnelevated {
    param([Parameter(Mandatory)][string]$Reason)

    Write-WinMintFirstLogonError $Reason
    Remove-Item -LiteralPath (Join-Path $logDir 'FirstLogon_self-elevation.flag') -Force -ErrorAction SilentlyContinue
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

# ΓöÇΓöÇ Elevation guarantee ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
# FirstLogon does machine-wide work (HKLM writes, service changes, autologon teardown).
# FirstLogonCommands usually hand an elevated token, but for a CUSTOM split-token admin
# account that is not guaranteed - a filtered (standard) token would make those operations
# fail with access-denied. If this instance is not elevated, re-launch it elevated via a
# Highest-privilege scheduled task (runs with the full admin token, no UAC prompt) and let
# that instance do the work. Harmless when already elevated.
$elevated = $false
try {
    $elevated = Test-WinMintTokenElevated
}
catch { $elevated = $false }
Set-WinMintFirstLogonContextElevated -Elevated $elevated
"$(Get-Date -Format 'o') FirstLogon running elevated: $elevated" | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
if (-not $elevated) {
    $elevFlag = Join-Path $logDir 'FirstLogon_self-elevation.flag'
    if (Test-Path -LiteralPath $elevFlag) {
        Stop-WinMintFirstLogonUnelevated -Reason 'FirstLogon is NOT elevated and self-elevation was already attempted; aborting before machine-wide setup so RunOnce can retry.'
    }
    else {
        try {
            Set-Content -LiteralPath $elevFlag -Value (Get-Date -Format o) -Encoding ASCII
            $exe = Resolve-WinMintPowerShellHost
            $taskName = 'WinMintFirstLogonElevated'
            $entryPath = (Get-WinMintFirstLogonContext).EntryPath
            $tr = "`"$exe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$entryPath`""
            & schtasks.exe /Create /TN $taskName /TR $tr /SC ONCE /ST 23:59 /RL HIGHEST /F 2>&1 | Out-Null
            $elevOk = ($LASTEXITCODE -eq 0)
            if ($elevOk) { & schtasks.exe /Run /TN $taskName 2>&1 | Out-Null; $elevOk = ($LASTEXITCODE -eq 0) }
            if ($elevOk) {
                "$(Get-Date -Format 'o') FirstLogon re-launched elevated via scheduled task '$taskName'; standard-token instance exiting." | Out-File (Join-Path $logDir 'FirstLogon.log') -Append
                try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
                exit 0
            }
            Stop-WinMintFirstLogonUnelevated -Reason 'Self-elevation scheduled task could not be created/started; aborting before machine-wide setup so RunOnce can retry.'
        }
        catch { Stop-WinMintFirstLogonUnelevated -Reason "Self-elevation failed: $_; aborting before machine-wide setup so RunOnce can retry." }
    }
}
