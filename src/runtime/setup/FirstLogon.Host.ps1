#Requires -Version 5.1

function Resolve-WinMintPowerShellHost {
    Resolve-WinMintPowerShell7Host
}


function Test-WinMintTokenElevated {
    Test-WinMintProcessElevated
}

function Install-WinMintFirstLogonPowerShellMinimum {
    # Fallback only: offline WIM staging is the primary source. Used when the
    # bundled host is missing or older than 7.6.0 before provisioning lock.
    $logPath = Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon.log'
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw 'PowerShell 7.6.0+ is missing/too old and winget.exe was not available for FirstLogon recovery install.'
    }

    "$(Get-Date -Format 'o') Installing PowerShell 7.6.0+ via winget (FirstLogon recovery; prefer offline WIM staging)." |
        Out-File -LiteralPath $logPath -Append
    & $winget.Source install `
        --id Microsoft.PowerShell `
        --source winget `
        --accept-package-agreements `
        --accept-source-agreements `
        --disable-interactivity `
        --silent | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "winget install Microsoft.PowerShell failed with exit code $LASTEXITCODE."
    }
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
            $modeVal = if ($ctx.ContainsKey('AgentMode') -and -not [string]::IsNullOrWhiteSpace([string]$ctx.AgentMode)) {
                [string]$ctx.AgentMode
            } else {
                'Auto'
            }
            $psArg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$entryPath`" -AgentMode $modeVal"
            # schtasks needs \"...\" around Program Files paths; Register-ScheduledTask Interactive alone stays filtered/UAC.
            & schtasks.exe /Delete /TN $taskName /F 2>$null | Out-Null
            $tr = '\"' + $exe + '\" ' + ($psArg -replace '"', '\"')
            $createOut = & schtasks.exe /Create /TN $taskName /TR $tr /SC ONCE /ST 23:59 /RL HIGHEST /F 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "schtasks /Create failed ($LASTEXITCODE): $createOut"
            }
            $runOut = & schtasks.exe /Run /TN $taskName 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "schtasks /Run failed ($LASTEXITCODE): $runOut"
            }
            "$(Get-Date -Format 'o') FirstLogon re-launched elevated via scheduled task '$taskName'; standard-token instance exiting." |
                Out-File -LiteralPath $logPath -Append
            try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
            return @{ ShouldExit = $true; ExitCode = 0 }
        }
        catch { Stop-WinMintFirstLogonUnelevated -Reason "Self-elevation failed: $_; aborting before machine-wide setup so RunOnce can retry." }
    }

    $minimum = Get-WinMintMinimumPowerShellVersion
    $currentMeetsMinimum = (
        $PSVersionTable.PSEdition -eq 'Core' -and
        $PSVersionTable.PSVersion -ge $minimum
    )

    if ($elevated -and -not $currentMeetsMinimum) {
        $p7Flag = Join-Path $ctx.LogDir 'FirstLogon_pwsh7.flag'
        $pwsh7 = $null
        try { $pwsh7 = Resolve-WinMintPowerShellHost } catch { $pwsh7 = $null }

        if ([string]::IsNullOrWhiteSpace([string]$pwsh7) -or -not (Test-WinMintPowerShellHostMeetsMinimum -Path $pwsh7 -Minimum $minimum)) {
            $installFlag = Join-Path $ctx.LogDir 'FirstLogon_pwsh76_install.flag'
            if (-not (Test-Path -LiteralPath $installFlag)) {
                try {
                    Set-Content -LiteralPath $installFlag -Value (Get-Date -Format o) -Encoding ASCII
                    Install-WinMintFirstLogonPowerShellMinimum
                    $pwsh7 = Resolve-WinMintPowerShellHost
                }
                catch {
                    Write-WinMintFirstLogonError "PowerShell $minimum+ is required for FirstLogon and recovery install failed: $_"
                    return @{ ShouldExit = $true; ExitCode = 1 }
                }
            }
            else {
                try { $pwsh7 = Resolve-WinMintPowerShellHost } catch { $pwsh7 = $null }
            }
        }

        if ([string]::IsNullOrWhiteSpace([string]$pwsh7) -or -not (Test-Path -LiteralPath $pwsh7 -PathType Leaf)) {
            Write-WinMintFirstLogonError "PowerShell $minimum+ is required for FirstLogon but was not found under Program Files\PowerShell\7."
            return @{ ShouldExit = $true; ExitCode = 1 }
        }
        if (-not (Test-WinMintPowerShellHostMeetsMinimum -Path $pwsh7 -Minimum $minimum)) {
            $found = Get-WinMintPowerShellHostVersion -Path $pwsh7
            Write-WinMintFirstLogonError "PowerShell $minimum+ is required for FirstLogon. Found $found at '$pwsh7'."
            return @{ ShouldExit = $true; ExitCode = 1 }
        }

        if (-not (Test-Path -LiteralPath $p7Flag)) {
            try {
                Set-Content -LiteralPath $p7Flag -Value (Get-Date -Format o) -Encoding ASCII
                "$(Get-Date -Format 'o') Re-launching FirstLogon under PowerShell $minimum+ ($pwsh7); the previous host waits for it." |
                    Out-File -LiteralPath $logPath -Append
                try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
                $modeVal = if ($ctx.ContainsKey('AgentMode') -and -not [string]::IsNullOrWhiteSpace([string]$ctx.AgentMode)) {
                    [string]$ctx.AgentMode
                } else {
                    'Auto'
                }
                $p7 = Start-Process -FilePath $pwsh7 -ArgumentList @(
                    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
                    '-File', "`"$($ctx.EntryPath)`"", '-AgentMode', $modeVal
                ) -Wait -PassThru
                return @{ ShouldExit = $true; ExitCode = ([int]$p7.ExitCode) }
            }
            catch {
                Write-WinMintFirstLogonError "PowerShell $minimum+ re-launch failed: $_"
                try { Start-Transcript -Path (Join-Path $ctx.LogDir 'FirstLogon_transcript.log') -Append -ErrorAction SilentlyContinue | Out-Null } catch { }
                return @{ ShouldExit = $true; ExitCode = 1 }
            }
        }

        Write-WinMintFirstLogonError "PowerShell $minimum+ handoff already attempted but this process is still $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))."
        return @{ ShouldExit = $true; ExitCode = 1 }
    }

    if (-not $currentMeetsMinimum) {
        Write-WinMintFirstLogonError "PowerShell $minimum+ is required for FirstLogon. Current host: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))."
        return @{ ShouldExit = $true; ExitCode = 1 }
    }

    "$(Get-Date -Format 'o') FirstLogon host: PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))" | Out-File -LiteralPath $logPath -Append
    return @{ ShouldExit = $false; ExitCode = 0 }
}
