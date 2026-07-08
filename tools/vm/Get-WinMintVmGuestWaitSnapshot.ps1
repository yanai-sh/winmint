#Requires -Version 5.1
<#
.SYNOPSIS
    Guest-side FirstLogon wait snapshot for VM acceptance polling.

.DESCRIPTION
    Dot-sourced by WinMint-VmConsole.ps1 and executed on the guest via PowerShell
    Direct (staged + guest pwsh 7). Emits JSON when run as a script.
#>
function Get-WinMintVmGuestWaitSnapshot {
    $snapshot = [ordered]@{
        stateExists = $false
        runStatus = ''
        currentStep = ''
        runningSteps = @()
        setupPhase = ''
        setupShellProgressPct = 0
        setupShellTaskLabel = ''
        setupShellProcessRunning = $false
        desktopGuardActive = $false
        breadcrumb = $false
        completedSteps = 0
        totalSteps = 0
    }

    $winMintDir = Join-Path $env:LOCALAPPDATA 'WinMint'
    $runtimeStatePath = Join-Path $winMintDir 'runtime-state.json'
    $runtimeState = $null
    if (Test-Path -LiteralPath $runtimeStatePath) {
        try {
            $runtimeState = Get-Content -LiteralPath $runtimeStatePath -Raw | ConvertFrom-Json
        }
        catch { }
    }

    $statePath = Join-Path $winMintDir 'state.json'
    if (Test-Path -LiteralPath $statePath) {
        $snapshot.stateExists = $true
        try {
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            if ($state.run -and $state.run.PSObject.Properties['status']) {
                $snapshot.runStatus = [string]$state.run.status
            }
            if ($state.steps) {
                foreach ($prop in $state.steps.PSObject.Properties) {
                    $snapshot.totalSteps++
                    $status = if ($prop.Value -and $prop.Value.PSObject.Properties['status']) {
                        [string]$prop.Value.status
                    } else { 'pending' }
                    if ($status -in @('ok', 'skipped')) { $snapshot.completedSteps++ }
                    if ($status -eq 'running') { $snapshot.runningSteps += [string]$prop.Name }
                }
            }
            if ($snapshot.runningSteps.Count -gt 0) {
                $snapshot.currentStep = [string]$snapshot.runningSteps[0]
            }
        }
        catch { }
    }

    if ($runtimeState -and $runtimeState.agent) {
        if ($runtimeState.agent.PSObject.Properties['runStatus']) {
            $snapshot.runStatus = [string]$runtimeState.agent.runStatus
        }
        if ($runtimeState.agent.PSObject.Properties['currentStep']) {
            $snapshot.currentStep = [string]$runtimeState.agent.currentStep
        }
        if ($runtimeState.agent.PSObject.Properties['completedSteps']) {
            $snapshot.completedSteps = [int]$runtimeState.agent.completedSteps
        }
        if ($runtimeState.agent.PSObject.Properties['totalSteps']) {
            $snapshot.totalSteps = [int]$runtimeState.agent.totalSteps
        }
        if ($runtimeState.agent.PSObject.Properties['runningSteps']) {
            $snapshot.runningSteps = @($runtimeState.agent.runningSteps)
        }
    }

    if ($runtimeState -and $runtimeState.control -and $runtimeState.control.PSObject.Properties['phase']) {
        $snapshot.setupPhase = [string]$runtimeState.control.phase
    }
    if ($runtimeState -and $runtimeState.display) {
        if ($runtimeState.display.PSObject.Properties['progressPct']) {
            $snapshot.setupShellProgressPct = [int]$runtimeState.display.progressPct
        }
        if ($runtimeState.display.PSObject.Properties['taskLabel']) {
            $snapshot.setupShellTaskLabel = [string]$runtimeState.display.taskLabel
        }
    }

    if ([string]::IsNullOrWhiteSpace($snapshot.setupPhase)) {
        $controlPath = Join-Path $winMintDir 'setup-shell-control.json'
        if (Test-Path -LiteralPath $controlPath) {
            try {
                $control = Get-Content -LiteralPath $controlPath -Raw | ConvertFrom-Json
                if ($control -and $control.PSObject.Properties['phase']) {
                    $snapshot.setupPhase = [string]$control.phase
                }
            }
            catch { }
        }
    }

    if ($snapshot.setupShellProgressPct -eq 0 -and [string]::IsNullOrWhiteSpace($snapshot.setupShellTaskLabel)) {
        $statusPath = Join-Path $winMintDir 'setup-shell-status.json'
        if (Test-Path -LiteralPath $statusPath) {
            try {
                $status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
                if ($status -and $status.PSObject.Properties['progressPct']) {
                    $snapshot.setupShellProgressPct = [int]$status.progressPct
                }
                if ($status -and $status.PSObject.Properties['taskLabel']) {
                    $snapshot.setupShellTaskLabel = [string]$status.taskLabel
                }
            }
            catch { }
        }
    }

    $snapshot.setupShellProcessRunning = [bool]@(
        Get-Process -Name 'WinMintSetupShell' -ErrorAction SilentlyContinue
    ).Count
    $noWinKeys = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name NoWinKeys -ErrorAction SilentlyContinue).NoWinKeys
    $snapshot.desktopGuardActive = ($noWinKeys -eq 1)
    $snapshot.breadcrumb = Test-Path -LiteralPath 'C:\ProgramData\WinMint\Logs\FirstLogonCommands-fired.txt'
    return [pscustomobject]$snapshot
}

if ($MyInvocation.InvocationName -ne '.') {
    Get-WinMintVmGuestWaitSnapshot | ConvertTo-Json -Depth 5 -Compress
}
