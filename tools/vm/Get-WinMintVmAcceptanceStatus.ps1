#Requires -Version 7.6
<#
.SYNOPSIS
    Poll the active managed VM acceptance run (for Cursor/agents).

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Get-WinMintVmAcceptanceStatus.ps1
#>
[CmdletBinding()]
param(
    [int]$Tail = 20,
    [int]$ProgressTail = 8
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WinMint-VmConsole.ps1')
$repoRoot = Set-WinMintVmRepoRoot -ToolsVmRoot $PSScriptRoot
$managedPath = Get-WinMintVmManagedRunPath -RepoRoot $repoRoot
$state = Read-WinMintVmManagedRunState -Path $managedPath

if (-not $state) {
    @{ found = $false; complete = $false; managedRunPath = $managedPath } | ConvertTo-Json -Depth 4
    exit 0
}

$pidValue = 0
if ($state.pid) { $pidValue = [int]$state.pid }
$running = Test-WinMintVmProcessAlive -ProcessId $pidValue
$runLog = [string]$state.runLog
$runEvents = [string]$state.runEvents
if (-not $runEvents -and $runLog) {
    $runEvents = Join-Path (Split-Path -Parent $runLog) 'run-events.jsonl'
}
$acceptanceResult = [string]$state.acceptanceResult
$verdict = $null
$plumbingVerdict = $null
$evidenceVerdict = $null
$warnings = @()
$reasons = @()
$errorMessage = [string]$state.error
$observePid = $null
$observeMode = $null
$buildStrategy = $null
$buildEstimatedMinutes = $null
if ($state.observePid) { $observePid = [int]$state.observePid }
if ($state.observeMode) { $observeMode = [string]$state.observeMode }
if ($state.buildStrategy) { $buildStrategy = [string]$state.buildStrategy }
if ($state.buildEstimatedMinutes) { $buildEstimatedMinutes = [string]$state.buildEstimatedMinutes }
$exitCode = if ($null -ne $state.exitCode) { [int]$state.exitCode } else { $null }
$logTail = @(Get-WinMintVmRunLogTail -RunLog $runLog -Tail $Tail)
$significantTail = @(Get-WinMintVmSignificantLogTail -RunLog $runLog -Tail $Tail)
$progress = Get-WinMintVmRunProgressFromEvents -EventsPath $runEvents
$recentEvents = @(Get-WinMintVmRunEventsTail -EventsPath $runEvents -Tail $ProgressTail)

$startedAt = $null
if ($state.startedAt) {
    try { $startedAt = [datetime]$state.startedAt } catch { }
}
$elapsedMinutes = $null
$overTimeBudget = $false
$timeBudgetMinutes = if ($state.timeBudgetMinutes) { [int]$state.timeBudgetMinutes } else { 30 }
if ($startedAt) {
    $elapsedMinutes = [math]::Round((([datetime]::UtcNow) - $startedAt.ToUniversalTime()).TotalMinutes, 1)
    $overTimeBudget = ($elapsedMinutes -gt $timeBudgetMinutes)
}

if ($acceptanceResult -and (Test-Path -LiteralPath $acceptanceResult)) {
    try {
        $result = Get-Content -LiteralPath $acceptanceResult -Raw | ConvertFrom-Json
        $verdict = [string]$result.verdict
        $reasons = @($result.reasons)
        if ($result.PSObject.Properties['plumbingVerdict']) { $plumbingVerdict = [string]$result.plumbingVerdict }
        if ($result.PSObject.Properties['evidenceVerdict']) { $evidenceVerdict = [string]$result.evidenceVerdict }
        if ($result.PSObject.Properties['warnings']) { $warnings = @($result.warnings) }
        $running = $false
    }
    catch { }
}

$status = [string]$state.status
if ($status -in @('passed', 'failed')) {
    $running = $false
}
elseif ($running) {
    $status = 'running'
}
else {
    if ($verdict -eq 'pass') { $status = 'passed' }
    elseif ($verdict -eq 'fail') { $status = 'failed' }
    elseif ($errorMessage) { $status = 'failed' }
    elseif ($null -ne $exitCode -and $exitCode -ne 0) { $status = 'failed' }
    elseif (@($significantTail) -match '(?i)\] \[ERROR\]|\] \[WARN \].*(Build failed|Exception:|throw |fatal error)') { $status = 'failed' }
    else { $status = 'stopped' }
}

$vmState = $null
$vmMissing = $false
$vmName = [string]$state.vmName
if ($vmName) {
    try {
        $vm = Get-VM -Name $vmName -ErrorAction Stop
        if ($vm) { $vmState = [string]$vm.State }
    }
    catch {
        if ($_.Exception.Message -match '(?i)not find|does not exist|cannot be found|unable to find') {
            $vmMissing = $true
            $vmState = 'missing'
        }
        else {
            $vmState = 'unknown (requires elevation)'
        }
    }
}

if ($running -and $pidValue -gt 0 -and -not (Test-WinMintVmProcessAlive -ProcessId $pidValue)) {
    $running = $false
    if ($status -eq 'running') {
        $status = 'stopped'
        if (-not $errorMessage) { $errorMessage = "Acceptance worker pid $pidValue is no longer running." }
    }
}

if ($running -and $vmMissing) {
    $buildPhase = ([string]$state.currentPhase -match '(?i)^Build') -or
        (@($significantTail) -match '(?i)=== Build ===|Stopping running test VM|Removed prior|Reusing cached ISO')
    if ($buildPhase) {
        $vmState = 'pending-recreate'
    }
    else {
        $running = $false
        $status = 'failed'
        $complete = $true
        if (-not $errorMessage) { $errorMessage = "VM '$vmName' not found (deleted or never created)." }
    }
}

$complete = ($status -in @('passed', 'failed'))

$inferredPhase = Get-WinMintVmInferredRunPhase -Tail @($significantTail) -StoredPhase ([string]$state.currentPhase)
$logFreshMinutes = Get-WinMintVmRunLogFreshnessMinutes -RunLog $runLog

$progressStaleMinutes = $null
$guestPollStalled = $false
$logStaleMinutes = $null
if ($running) {
    if ($progress.lastProgressAt) {
        try {
            $lastProgress = [datetime]$progress.lastProgressAt
            $progressStaleMinutes = [math]::Round(((Get-Date) - $lastProgress).TotalMinutes, 1)
            $phase = if ($inferredPhase) { $inferredPhase } else { [string]$state.currentPhase }
            if ($progressStaleMinutes -gt 10 -and $phase -match '(?i)FirstLogon|Wait') {
                $guestPollStalled = $true
            }
        }
        catch { }
    }
    elseif ($null -ne $logFreshMinutes -and $logFreshMinutes -gt 10 -and $inferredPhase -match '(?i)BuildBoot|Build') {
        $logStaleMinutes = $logFreshMinutes
    }
}

if (-not $buildStrategy -and $progress.buildStrategy) { $buildStrategy = [string]$progress.buildStrategy }
if (-not $buildEstimatedMinutes -and $progress.buildEstimatedMinutes) { $buildEstimatedMinutes = [string]$progress.buildEstimatedMinutes }

[ordered]@{
    found = $true
    complete = $complete
    status = $status
    running = $running
    pid = $pidValue
    exitCode = $exitCode
    error = $errorMessage
    currentPhase = if ($inferredPhase) { $inferredPhase } else { [string]$state.currentPhase }
    vmName = $vmName
    vmState = $vmState
    evidenceDir = [string]$state.evidenceDir
    runLog = $runLog
    runEvents = $runEvents
    observePid = $observePid
    observeMode = $observeMode
    buildStrategy = $buildStrategy
    buildEstimatedMinutes = $buildEstimatedMinutes
    managedRunPath = $managedPath
    acceptanceResult = $acceptanceResult
    verdict = $verdict
    plumbingVerdict = $plumbingVerdict
    evidenceVerdict = $evidenceVerdict
    reasons = $reasons
    warnings = $warnings
    startedAt = [string]$state.startedAt
    elapsedMinutes = $elapsedMinutes
    timeBudgetMinutes = $timeBudgetMinutes
    overTimeBudget = $overTimeBudget
    progressStaleMinutes = $progressStaleMinutes
    guestPollStalled = $guestPollStalled
    logStaleMinutes = $logStaleMinutes
    progress = $progress
    recentEvents = $recentEvents
    tail = $logTail
    significantTail = $significantTail
    updatedAt = [string]$state.updatedAt
} | ConvertTo-Json -Depth 8
