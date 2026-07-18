#Requires -Version 7.6
<#
.SYNOPSIS
    Start a VM acceptance run for Cursor/agents — detached, logged, pollable.

.DESCRIPTION
    Writes output\vm-acceptance\managed-run.json, starts Invoke-WinMintVmAcceptance.ps1
    in a background pwsh process, and prints a JSON handle on stdout. Requires an
    already-elevated shell (no UAC relaunch). Reuses cached ISO/checkpoint when
    fingerprints match (SmartBuild on by default). Use -PushOnly for fast
    FirstLogon iteration (~2-8 min). Pass -ForceBuild only when image staging changed.
    Managed runs default to headless (-NoObserve): PS Direct polling does not need
    VMConnect; pass -Observe to open VMConnect Basic for manual splash watching.

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Start-WinMintVmAcceptanceManaged.ps1 `
        -ProfilePath .\tests\profiles\hyper-v-smoke-arm64.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProfilePath,
    [string]$VMName = 'WinMint-ARM-Test',
    [int]$MemoryGB = 6,
    [int]$DiskGB = 100,
    [int]$CpuCount = 4,
    [string]$SwitchName,
    [switch]$SkipBuild,
    [switch]$ForceBuild,
    [switch]$UseCheckpoint,
    [switch]$PushOnly,
    [switch]$SmartBuild,
    [switch]$FullImage,
    [ValidateSet('Auto', 'Full', 'Smoke')]
    [string]$Tier = 'Auto',
    [int]$TimeoutMinutes = 0,
    [int]$TimeBudgetMinutes = 0,
    [string]$SourceIso = '',
    [switch]$NoObserve,
    [switch]$Observe,
    [switch]$NoLogViewer,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WinMint-VmConsole.ps1')

if ($Observe) { $NoObserve = $false }
elseif (-not $PSBoundParameters.ContainsKey('NoObserve')) {
    $NoObserve = $true
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw 'VM acceptance requires an elevated PowerShell session (Hyper-V and DISM). Open an elevated terminal — UAC relaunch is not used.'
}

$repoRoot = Set-WinMintVmRepoRoot -ToolsVmRoot $PSScriptRoot
$managedPath = Get-WinMintVmManagedRunPath -RepoRoot $repoRoot
$acceptanceScript = Join-Path $PSScriptRoot 'Invoke-WinMintVmAcceptance.ps1'
$resolvedProfile = if ([IO.Path]::IsPathRooted($ProfilePath)) { $ProfilePath } else { Join-Path $repoRoot $ProfilePath }
if (-not (Test-Path -LiteralPath $resolvedProfile)) { throw "Build profile not found: $resolvedProfile" }

if (-not $PSBoundParameters.ContainsKey('SmartBuild')) { $SmartBuild = $true }
$profileJson = Get-Content -LiteralPath $resolvedProfile -Raw | ConvertFrom-Json
$buildPlan = $null
if (-not $SkipBuild) {
    $useCheckpointEffective = $UseCheckpoint.IsPresent -or (-not $ForceBuild -and -not $PushOnly)
    $buildPlan = Resolve-WinMintVmAcceptanceBuildPlan -RepoRoot $repoRoot -ProfilePath $resolvedProfile `
        -ProfileJson $profileJson -VMName $VMName -ForceBuild:$ForceBuild `
        -UseCheckpoint:$useCheckpointEffective -PushOnly:$PushOnly -SmartBuild:$SmartBuild `
        -Quality $(if ($FullImage) { 'max' } else { 'fast' })
    $ForceBuild = [bool]$buildPlan.ForceBuild
}

$prev = Read-WinMintVmManagedRunState -Path $managedPath
if ($prev -and $prev.pid -and (Test-WinMintVmProcessAlive -ProcessId ([int]$prev.pid))) {
    if (-not $Force) {
        throw "VM acceptance already running (pid $($prev.pid)). Pass -Force to stop it and start a new run."
    }
    Stop-WinMintVmProcessTree -ProcessId ([int]$prev.pid)
}

$startedAt = Get-Date
$evidenceDir = Join-Path $repoRoot ("output\vm-acceptance\$VMName-" + $startedAt.ToString('yyyyMMdd-HHmmss'))
$null = New-Item -ItemType Directory -Path $evidenceDir -Force
$runLog = Join-Path $evidenceDir 'run.log'
$null = New-Item -ItemType File -Path $runLog -Force

$timeBudget = if ($TimeBudgetMinutes -gt 0) { $TimeBudgetMinutes } else { 30 }
$runEvents = Initialize-WinMintVmRunLog -LogPath $runLog -Meta ([ordered]@{
        startedAt = $startedAt.ToString('o')
        runId = Split-Path -Leaf $evidenceDir
        vmName = $VMName
        tier = $Tier
        profile = $resolvedProfile
        managedRun = 'true'
        hostPid = $PID
        evidenceDir = $evidenceDir
        eventsFile = (Join-Path $evidenceDir 'run-events.jsonl')
        timeBudgetMinutes = $timeBudget
        pollCommand = 'pwsh -NoProfile -File .\tools\vm\Get-WinMintVmAcceptanceStatus.ps1'
    })
if ($buildPlan) {
    Write-WinMintVmRunEvent -Kind 'build-plan' -Payload @{
        strategy = [string]$buildPlan.Strategy
        estimatedMinutes = [string]$buildPlan.EstimatedMinutes
        isoCached = [bool]$buildPlan.IsoCached
        checkpointUsable = [bool]$buildPlan.CheckpointUsable
        agentChanged = [bool]$buildPlan.AgentChanged
    }
}

$logViewerOpened = $false
if (-not $NoLogViewer) {
    $logViewerOpened = Start-WinMintVmRunLogViewerInWindowsTerminal `
        -RunLog $runLog `
        -StartingDirectory $repoRoot `
        -TabTitle "WinMint VM $VMName" `
        -Tail 30
}

$pwsh = Resolve-WinMintPwshHostPath
$childArgs = @(
    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', $acceptanceScript,
    '-ManagedRun',
    '-ProfilePath', $resolvedProfile,
    '-VMName', $VMName,
    '-MemoryGB', $MemoryGB,
    '-DiskGB', $DiskGB,
    '-CpuCount', $CpuCount,
    '-Tier', $Tier,
    '-EvidenceDir', $evidenceDir
)
if ($TimeoutMinutes -gt 0) { $childArgs += @('-TimeoutMinutes', $TimeoutMinutes) }
if ($TimeBudgetMinutes -gt 0) { $childArgs += @('-TimeBudgetMinutes', $TimeBudgetMinutes) }
if ($SwitchName) { $childArgs += @('-SwitchName', $SwitchName) }
if ($SkipBuild) { $childArgs += '-SkipBuild' }
if ($ForceBuild) { $childArgs += '-ForceBuild' }
if ($UseCheckpoint) { $childArgs += '-UseCheckpoint' }
if ($PushOnly) { $childArgs += '-PushOnly' }
if ($SmartBuild) { $childArgs += '-SmartBuild' }
if ($FullImage) { $childArgs += '-FullImage' }
if (-not [string]::IsNullOrWhiteSpace($SourceIso)) { $childArgs += @('-SourceIso', $SourceIso) }
if ($NoObserve) { $childArgs += '-NoObserve' }

$errLog = Join-Path $evidenceDir 'run.err.log'
$proc = Start-Process -FilePath $pwsh -ArgumentList $childArgs -WorkingDirectory $repoRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput $runLog -RedirectStandardError $errLog

$handle = [ordered]@{
    status = 'starting'
    pid = $proc.Id
    profile = $resolvedProfile
    vmName = $VMName
    evidenceDir = $evidenceDir
    runLog = $runLog
    runEvents = $runEvents
    managedRunPath = $managedPath
    acceptanceResult = Join-Path $evidenceDir 'acceptance-result.json'
    startedAt = $startedAt.ToString('o')
    currentPhase = 'starting'
    timeBudgetMinutes = $timeBudget
    logViewerOpened = [bool]$logViewerOpened
    observeMode = if ($NoObserve) { 'headless' } else { 'basic' }
    pollCommand = "pwsh -NoProfile -File .\tools\vm\Get-WinMintVmAcceptanceStatus.ps1"
    tailCommand = "Get-Content -LiteralPath '$runLog' -Wait -Tail 30"
}
if ($buildPlan) {
    $handle.buildStrategy = [string]$buildPlan.Strategy
    $handle.buildEstimatedMinutes = [string]$buildPlan.EstimatedMinutes
    $handle.isoCached = [bool]$buildPlan.IsoCached
    $handle.checkpointUsable = [bool]$buildPlan.CheckpointUsable
}
Write-WinMintVmManagedRunState -Path $managedPath -State $handle

Start-Sleep -Seconds 2
if ($proc.HasExited) {
    $currentState = Get-Content -LiteralPath $managedPath | ConvertFrom-Json
    if ($currentState.status -ne 'failed') {
        $bootError = "Acceptance process exited immediately (exit code $($proc.ExitCode))."
        Write-WinMintVmLogLine -Message $bootError -LogPath $runLog -Level 'ERROR'
        Write-WinMintVmRunEvent -Kind 'verdict' -Payload @{ verdict = 'fail'; reason = 'boot-failed'; exitCode = $proc.ExitCode }
        $currentState.status = 'failed'
        $currentState.currentPhase = 'boot-failed'
        $currentState | Add-Member -MemberType NoteProperty -Name 'error' -Value $bootError -Force
        Write-WinMintVmManagedRunState -Path $managedPath -State $currentState
        throw $bootError
    }
    else {
        throw "Acceptance process exited immediately (exit code $($proc.ExitCode)). Reason: $($currentState.error)"
    }
}

$handle | ConvertTo-Json -Depth 6
