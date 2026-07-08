#Requires -Version 7.6
<#
.SYNOPSIS
    Integration test for provisioning-lock engage/release (guard + status pump + native host).

.EXAMPLE
    pwsh -NoProfile -File .\tests\integration\Test-WinMintProvisioningLockPreview.ps1 -StageDemo -Quick

.EXAMPLE
    pwsh -NoProfile -File .\tests\integration\Test-WinMintProvisioningLockPreview.ps1 -Stop
#>
[CmdletBinding(DefaultParameterSetName = 'Start')]
param(
    [Parameter(ParameterSetName = 'Stop')]
    [switch]$Stop,

    [Parameter(ParameterSetName = 'Start')]
    [int]$DwellMs = 1500,

    [Parameter(ParameterSetName = 'Start')]
    [switch]$Quick,

    [Parameter(ParameterSetName = 'Start')]
    [switch]$StageDemo,

    [Parameter(ParameterSetName = 'Start')]
    [int]$StageIntervalSeconds = 3,

    [Parameter(ParameterSetName = 'Start')]
    [ValidateSet('complete', 'failed', 'reboot')]
    [string]$ReleasePhase = 'complete',

    [Parameter(ParameterSetName = 'Start')]
    [ValidateSet('x64', 'arm64', '')]
    [string]$Arch = '',

    [Parameter(ParameterSetName = 'Start')]
    [switch]$DevKeyboardEscape,

    [Parameter(ParameterSetName = 'Start')]
    [switch]$ProductionLock
)

$ErrorActionPreference = 'Stop'
$testSupport = Join-Path (Split-Path -Parent $PSScriptRoot) 'setup-shell\SetupShell.TestSupport.ps1'
. $testSupport
if (-not $Arch) {
    $Arch = Get-WinMintHostSetupShellBinArch
}

function Get-WinMintProvisioningLockPreviewPaths {
    param([Parameter(Mandatory)][string]$Root)

    $previewRoot = Join-Path $Root 'output\setup-shell-preview'
    [ordered]@{
        PreviewRoot = $previewRoot
        PayloadDir  = $previewRoot
        ShellRoot   = Join-Path $previewRoot 'setup-shell'
        SessionPath = Join-Path $previewRoot 'preview-session.json'
        StopPath    = Join-Path $previewRoot 'stop.requested'
        AgentRoot   = Join-Path $previewRoot 'WinMintAgent'
    }
}

function Write-WinMintFirstLogonError {
    param([string]$Message)
    Write-Warning $Message
}

function Initialize-WinMintProvisioningLockPreviewAssets {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][hashtable]$Paths
    )

    foreach ($dir in @($Paths.PreviewRoot, $Paths.ShellRoot, $Paths.AgentRoot)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }

    Copy-Item -LiteralPath (Join-Path $RepoRoot 'assets\brand\winmint_hero_ui.png') `
        -Destination (Join-Path $Paths.ShellRoot 'winmint_hero_ui.png') -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'assets\runtime\setup\setup-shell\tokens.json') `
        -Destination (Join-Path $Paths.ShellRoot 'tokens.json') -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'src\runtime\firstlogon\agent-module-catalog.json') `
        -Destination (Join-Path $Paths.AgentRoot 'agent-module-catalog.json') -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'tests\profiles\hyper-v-smoke-arm64.json') `
        -Destination (Join-Path $Paths.AgentRoot 'BuildProfile.json') -Force
    @{
        profileName = 'Local Preview'
        profile     = 'Local Preview'
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Paths.PreviewRoot 'WinMintSetupProfile.json') -Encoding utf8
}

function Stop-WinMintProvisioningLockPreviewSession {
    param(
        [Parameter(Mandatory)][hashtable]$Paths,
        [string]$ReleasePhase = 'complete',
        [int]$WaitSeconds = 20
    )

    $proc = $null
    if (Test-Path -LiteralPath $Paths.SessionPath) {
        try {
            $session = Get-Content -LiteralPath $Paths.SessionPath -Raw | ConvertFrom-Json
            if ($session.PSObject.Properties['releasePhase'] -and [string]::IsNullOrWhiteSpace($ReleasePhase)) {
                $ReleasePhase = [string]$session.releasePhase
            }
            if ($session.PSObject.Properties['pid']) {
                $proc = Get-Process -Id ([int]$session.pid) -ErrorAction SilentlyContinue
            }
        }
        catch { }
    }
    if (-not $proc) {
        $proc = Get-Process -Name 'WinMintSetupShell' -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    Set-WinMintSetupShellControl -Phase $ReleasePhase -ProfileName 'Local Preview'
    Update-WinMintSetupShellStatus | Out-Null

    if ($proc) {
        Wait-WinMintProvisioningHost -Process $proc -TimeoutSeconds $WaitSeconds
    }
    else {
        Stop-WinMintProvisioningHostResidual
    }

    Remove-Item -LiteralPath $Paths.StopPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Paths.SessionPath -Force -ErrorAction SilentlyContinue
}

function Set-WinMintProvisioningLockPreviewAgentState {
    param([Parameter(Mandatory)][string]$RuntimeStepName)

    $statePath = Join-Path $env:LOCALAPPDATA 'WinMint\state.json'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $statePath) -Force
    @{
        run   = @{ status = 'running' }
        steps = @{
            "module:$RuntimeStepName" = @{
                status    = 'running'
                updatedAt = (Get-Date -Format o)
            }
        }
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding utf8
}

function Wait-WinMintProvisioningLockPreviewSession {
    param(
        [Parameter(Mandatory)]$Process,
        [Parameter(Mandatory)][hashtable]$Paths,
        [Parameter(Mandatory)][string]$ShellRoot,
        [string]$ReleasePhase,
        [int]$DwellMs,
        [switch]$StageDemo,
        [int]$StageIntervalSeconds,
        [switch]$DevKeyboardEscape
    )

    $stages = @(
        { Update-WinMintSetupShellStatus -ShellRoot $ShellRoot -PreAgentStage 'locked' | Out-Null }
        { Update-WinMintSetupShellStatus -ShellRoot $ShellRoot -PreAgentStage 'region' | Out-Null }
        { Update-WinMintSetupShellStatus -ShellRoot $ShellRoot -PreAgentStage 'defaults' | Out-Null }
        {
            Set-WinMintProvisioningLockPreviewAgentState -RuntimeStepName 'package-managers'
            Update-WinMintSetupShellStatus -ShellRoot $ShellRoot -PreAgentStage 'agent' | Out-Null
        }
        {
            Set-WinMintSetupShellControl -Phase 'finishing' -ProfileName 'Local Preview'
            Update-WinMintSetupShellStatus -ShellRoot $ShellRoot | Out-Null
        }
    )
    $stageIndex = 0
    $nextStageAt = if ($StageDemo) { (Get-Date).AddSeconds($StageIntervalSeconds) } else { [datetime]::MaxValue }
    $stopRequested = $false

    while (-not $Process.HasExited -and -not $stopRequested) {
        if (Test-Path -LiteralPath $Paths.StopPath) { $stopRequested = $true; break }
        if ($DevKeyboardEscape -and [Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -in @('Q', 'Enter', 'Escape')) { $stopRequested = $true; break }
        }
        if ($StageDemo -and (Get-Date) -ge $nextStageAt) {
            & $stages[$stageIndex]
            $stageIndex = ($stageIndex + 1) % $stages.Count
            $nextStageAt = (Get-Date).AddSeconds($StageIntervalSeconds)
        }
        Invoke-WinMintSetupShellStatusPumpTick -ShellRoot $ShellRoot
        Start-Sleep -Milliseconds 200
    }

    if (-not $Process.HasExited) {
        Stop-WinMintProvisioningLockPreviewSession -Paths $Paths -ReleasePhase $ReleasePhase `
            -WaitSeconds ([Math]::Max(10, [int]($DwellMs / 1000) + 5))
    }
}

$repoRoot = Get-WinMintTestRepoRoot -ScriptRoot $PSScriptRoot
$paths = Get-WinMintProvisioningLockPreviewPaths -Root $repoRoot

$setupRoot = Join-Path $repoRoot 'src\runtime\setup'
. (Join-Path $setupRoot 'WinMint.Runtime.Common.ps1')
. (Join-Path $setupRoot 'FirstLogon.Context.ps1')
. (Join-Path $setupRoot 'FirstLogon.State.ps1')
. (Join-Path $setupRoot 'WinMintSetupShell.Status.ps1')
. (Join-Path $setupRoot 'ProvisioningGuard.ps1')

$logDir = Join-Path $env:LOCALAPPDATA 'WinMint\Logs'
$null = New-Item -ItemType Directory -Path $logDir -Force
Set-WinMintFirstLogonContext -Context (New-WinMintFirstLogonContext @{
        LogDir          = $logDir
        PayloadDir      = [string]$paths.PayloadDir
        EntryPath       = $PSCommandPath
        MaxAttempts     = 3
        SetupScriptRoot = [string]$paths.PayloadDir
        Elevated        = $true
    })

if ($Stop) {
    Stop-WinMintProvisioningLockPreviewSession -Paths $paths
    Write-Host 'Provisioning lock preview stopped and guard cleared.'
    exit 0
}

if ($Quick) { $DwellMs = 400 }

$exePath = Get-WinMintSetupShellExePath -Root $repoRoot -Arch $Arch
Initialize-WinMintProvisioningLockPreviewAssets -RepoRoot $repoRoot -Paths $paths
Remove-Item -LiteralPath $paths.StopPath, $paths.SessionPath -Force -ErrorAction SilentlyContinue

$shellRoot = Get-WinMintSetupShellRoot
Set-WinMintSetupShellControl -Phase 'running' -ProfileName 'Local Preview'
Update-WinMintSetupShellStatus -ShellRoot $shellRoot -PreAgentStage 'locked' | Out-Null
if ($ProductionLock) { Enable-WinMintProvisioningGuard }
else { Enable-WinMintProvisioningGuard -AllowTaskSwitch }
Start-WinMintSetupShellStatusPump -PollIntervalMs 500 | Out-Null

$proc = Start-WinMintProvisioningHost -PollIntervalMs 500 -HostExePath $exePath `
    -MinStartDwellMs $DwellMs -MinCompleteDwellMs $DwellMs
@{
    pid          = $proc.Id
    startedAt    = (Get-Date -Format o)
    releasePhase = $ReleasePhase
    stopPath     = $paths.StopPath
} | ConvertTo-Json | Set-Content -LiteralPath $paths.SessionPath -Encoding utf8

Write-Host 'Provisioning lock preview running. End with -Stop or stop.requested file.'
Write-Host "Log: $logDir\SetupShell.log"

try {
    Wait-WinMintProvisioningLockPreviewSession -Process $proc -Paths $paths -ShellRoot $shellRoot `
        -ReleasePhase $ReleasePhase -DwellMs $DwellMs -StageDemo:$StageDemo `
        -StageIntervalSeconds $StageIntervalSeconds -DevKeyboardEscape:$DevKeyboardEscape
}
finally {
    Stop-WinMintSetupShellStatusPump
    if (-not $proc.HasExited) { $proc | Stop-Process -Force -ErrorAction SilentlyContinue }
    Stop-WinMintProvisioningHostResidual
    Remove-Item -LiteralPath $paths.StopPath, $paths.SessionPath -Force -ErrorAction SilentlyContinue
}

if ($proc.HasExited -and $proc.ExitCode -ne 0) {
    throw "WinMintSetupShell.exe exited with code $($proc.ExitCode)."
}

Write-Host 'Provisioning lock preview ended.'
