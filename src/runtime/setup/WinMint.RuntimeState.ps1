#Requires -Version 7.6

function Get-WinMintRuntimeStatePath {
    Join-Path (Join-Path $env:LOCALAPPDATA 'WinMint') 'runtime-state.json'
}

function Read-WinMintRuntimeState {
    $path = Get-WinMintRuntimeStatePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch { return $null }
}

function New-WinMintRuntimeStateAgentDisplay {
    param([object]$AgentState)

    $display = [ordered]@{
        runStatus = ''
        currentStep = ''
        runningSteps = @()
        completedSteps = 0
        totalSteps = 0
        updatedAt = (Get-Date -Format o)
    }

    if (-not $AgentState) { return $display }

    if ($AgentState.run -and $AgentState.run.PSObject.Properties['status']) {
        $display.runStatus = [string]$AgentState.run.status
    }

    if ($AgentState.steps) {
        foreach ($prop in $AgentState.steps.PSObject.Properties) {
            $display.totalSteps++
            $status = if ($prop.Value -and $prop.Value.PSObject.Properties['status']) {
                [string]$prop.Value.status
            }
            else { 'pending' }
            if ($status -in @('ok', 'skipped')) { $display.completedSteps++ }
            if ($status -eq 'running') { $display.runningSteps += [string]$prop.Name }
        }
    }

    if (@($display.runningSteps).Count -gt 0) {
        $display.currentStep = [string]$display.runningSteps[0]
    }

    return $display
}

function Write-WinMintRuntimeState {
    param(
        $Control,
        $Display,
        $Agent
    )

    if ($null -eq $Control -and $null -eq $Display -and $null -eq $Agent) { return }

    $path = Get-WinMintRuntimeStatePath
    $existing = Read-WinMintRuntimeState
    $startedAt = if ($existing -and $existing.control -and $existing.control.PSObject.Properties['startedAt']) {
        [string]$existing.control.startedAt
    }
    elseif ($Control -and $Control.PSObject.Properties['startedAt']) {
        [string]$Control.startedAt
    }
    else {
        (Get-Date -Format o)
    }

    $controlSection = if ($null -ne $Control) {
        [ordered]@{
            phase = [string]$Control.phase
            startedAt = if ($Control.PSObject.Properties['startedAt'] -and $Control.startedAt) { [string]$Control.startedAt } else { $startedAt }
            updatedAt = if ($Control.PSObject.Properties['updatedAt'] -and $Control.updatedAt) { [string]$Control.updatedAt } else { (Get-Date -Format o) }
            profileName = if ($Control.PSObject.Properties['profileName']) { [string]$Control.profileName } else { '' }
            message = if ($Control.PSObject.Properties['message']) { [string]$Control.message } else { '' }
            preAgentStage = if ($Control.PSObject.Properties['preAgentStage']) { [string]$Control.preAgentStage } else { '' }
        }
    }
    elseif ($existing -and $existing.control) {
        $existing.control
    }
    else {
        [ordered]@{
            phase = 'running'
            startedAt = $startedAt
            updatedAt = (Get-Date -Format o)
            profileName = ''
            message = ''
            preAgentStage = ''
        }
    }

    $displaySection = if ($null -ne $Display) { $Display } elseif ($existing -and $existing.display) { $existing.display } else { $null }
    $agentSection = if ($null -ne $Agent) { $Agent } elseif ($existing -and $existing.agent) { $existing.agent } else {
        New-WinMintRuntimeStateAgentDisplay -AgentState $null
    }

    if ($null -eq $displaySection) {
        $displaySection = [ordered]@{
            phase = [string]$controlSection.phase
            groupLabel = 'Setting up'
            taskLabel = 'Working…'
            stepIndex = 1
            stepTotal = 1
            progressPct = 0
            progressMode = 'indeterminate'
            profileName = [string]$controlSection.profileName
            elapsedMs = 0
            steps = @()
            banner = ''
            bannerKind = ''
            logDir = ''
            updatedAt = (Get-Date -Format o)
        }
    }

    $payload = [ordered]@{
        schemaVersion = 1
        updatedAt = (Get-Date -Format o)
        control = $controlSection
        display = $displaySection
        agent = $agentSection
    }

    if (Get-Command Save-WinMintAtomicJson -ErrorAction SilentlyContinue) {
        Save-WinMintAtomicJson -Path $path -Data $payload -Depth 12
        return
    }

    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($path, ($payload | ConvertTo-Json -Depth 12 -Compress:$false), $utf8)
}

function Sync-WinMintRuntimeStateFromLegacy {
    $winMintDir = Join-Path $env:LOCALAPPDATA 'WinMint'
    $controlPath = Join-Path $winMintDir 'setup-shell-control.json'
    $statusPath = Join-Path $winMintDir 'setup-shell-status.json'
    $agentStatePath = Join-Path $winMintDir 'state.json'

    $control = $null
    $display = $null
    $agentState = $null

    if (Test-Path -LiteralPath $controlPath -PathType Leaf) {
        try { $control = Get-Content -LiteralPath $controlPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    if (Test-Path -LiteralPath $statusPath -PathType Leaf) {
        try { $display = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    if (Test-Path -LiteralPath $agentStatePath -PathType Leaf) {
        try { $agentState = Get-Content -LiteralPath $agentStatePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }

    if ($null -eq $control -and $null -eq $display -and $null -eq $agentState) { return $null }

    Write-WinMintRuntimeState `
        -Control $control `
        -Display $display `
        -Agent (New-WinMintRuntimeStateAgentDisplay -AgentState $agentState)
    return Read-WinMintRuntimeState
}

function Import-WinMintRuntimeStateModule {
    if (Get-Command Write-WinMintRuntimeState -ErrorAction SilentlyContinue) { return }
    foreach ($candidate in @(
            (Join-Path $PSScriptRoot 'WinMint.RuntimeState.ps1')
            (Join-Path (Split-Path -Parent $PSScriptRoot) 'WinMint.RuntimeState.ps1')
        )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            . $candidate
            return
        }
    }
}
