#Requires -Version 7.6
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
    Write-Error $Message -ErrorAction Continue
}

$setupRoot = Join-Path $root 'src\runtime\setup'
. (Join-Path $setupRoot 'WinMint.Runtime.Common.ps1')
. (Join-Path $setupRoot 'FirstLogon.Context.ps1')
. (Join-Path $setupRoot 'WinMintSetupShell.Status.ps1')

$previewRoot = Join-Path $root 'output\projection-test'
$null = New-Item -ItemType Directory -Path (Join-Path $previewRoot 'WinMintAgent') -Force
Copy-Item -LiteralPath (Join-Path $root 'tests\profiles\hyper-v-smoke-arm64.json') `
    -Destination (Join-Path $previewRoot 'WinMintAgent\BuildProfile.json') -Force
Copy-Item -LiteralPath (Join-Path $root 'src\runtime\firstlogon\agent-module-catalog.json') `
    -Destination (Join-Path $previewRoot 'WinMintAgent\agent-module-catalog.json') -Force
@{
    profileName = 'Projection Test'
    profile     = 'Projection Test'
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $previewRoot 'WinMintSetupProfile.json') -Encoding utf8

$logDir = Join-Path $env:TEMP 'winmint-projection-test'
$null = New-Item -ItemType Directory -Path $logDir -Force
Set-WinMintFirstLogonContext -Context (New-WinMintFirstLogonContext @{
        LogDir          = $logDir
        PayloadDir      = $previewRoot
        EntryPath       = $PSCommandPath
        MaxAttempts     = 3
        SetupScriptRoot = $previewRoot
        Elevated        = $true
    })

$control = @{
    phase = 'running'
    profileName = 'Projection Test'
    startedAt = (Get-Date).AddMinutes(-2).ToString('o')
    preAgentStage = ''
}
$agentState = $null
$agentProfile = Get-Content -LiteralPath (Join-Path $previewRoot 'WinMintAgent\BuildProfile.json') -Raw | ConvertFrom-Json

$locked = Get-WinMintProvisioningProjection -Control $control -AgentState $agentState -AgentProfile $agentProfile -LogDir $logDir -PreAgentStage 'locked'
if ($locked.groupLabel -ne 'Preparing system') {
    Add-Failure "locked stage groupLabel expected 'Preparing system', got '$($locked.groupLabel)'."
}
if ($locked.taskLabel -notmatch 'Lock desktop') {
    Add-Failure "locked stage taskLabel should reflect prepare shell title, got '$($locked.taskLabel)'."
}
if ($locked.progressMode -ne 'indeterminate') {
    Add-Failure "locked stage progressMode expected indeterminate, got '$($locked.progressMode)'."
}
if (@($locked.steps).Count -lt 3) {
    Add-Failure "locked stage should emit visible setup steps."
}

$region = Get-WinMintProvisioningProjection -Control $control -AgentState $agentState -AgentProfile $agentProfile -LogDir $logDir -PreAgentStage 'region'
if ($region.groupLabel -ne 'Restoring your region') {
    Add-Failure "region stage groupLabel expected 'Restoring your region', got '$($region.groupLabel)'."
}
if ($region.progressMode -ne 'indeterminate') {
    Add-Failure "region stage progressMode expected indeterminate before agent, got '$($region.progressMode)'."
}

$finishing = Get-WinMintProvisioningProjection -Control (@{ phase = 'finishing'; profileName = 'Projection Test'; startedAt = (Get-Date).ToString('o') }) `
    -AgentState $agentState -AgentProfile $agentProfile -LogDir $logDir
if ($finishing.groupLabel -ne 'Finishing setup') {
    Add-Failure "finishing phase groupLabel expected 'Finishing setup', got '$($finishing.groupLabel)'."
}
if ($finishing.taskLabel -notmatch 'shell pins|desktop lock') {
    Add-Failure "finishing taskLabel should reflect finalize shell work, got '$($finishing.taskLabel)'."
}
if ($finishing.progressPct -lt 90) {
    Add-Failure "finishing progressPct should be near complete, got $($finishing.progressPct)."
}

$passed = $false
$prepareStatus = Get-WinMintSetupShellGroupStepStatus -GroupId 'prepare' -CurrentGroupId 'prepare' `
    -Phase 'running' -PreAgentStage 'locked' -Progress @{ CompletedCount = 0; CurrentRuntimeStep = '' } -PassedCurrent ([ref]$passed)
if ($prepareStatus -ne 'current') {
    Add-Failure "prepare group should be current when locked, got '$prepareStatus'."
}

$eventLog = Join-Path $logDir 'WinMintAgent-events.jsonl'
@(
    '{"time":"2026-01-01T00:00:00+00:00","type":"install","status":"running","message":"Installing voidtools.Everything.Beta for amd64."}'
) | Set-Content -LiteralPath $eventLog -Encoding utf8
$agentWithEvents = @{
    run = @{ progressEventLog = $eventLog }
    steps = @{
        'module:package-managers' = @{
            status = 'running'
            startedAt = (Get-Date).AddSeconds(-30).ToString('o')
        }
    }
} | ConvertTo-Json -Depth 6 | ConvertFrom-Json

$liveHint = Get-WinMintSetupShellLiveTaskHint -AgentState $agentWithEvents
if ($liveHint -notmatch 'Everything') {
    Add-Failure "event log hint should surface install message, got '$liveHint'."
}
$liveLabel = Resolve-WinMintSetupShellRunningTaskLabel `
    -RuntimeStepName 'package-managers' `
    -Phase 'running' `
    -FallbackLabel 'Bootstrap winget and Scoop' `
    -ProfileDisplayName 'Projection Test' `
    -AgentState $agentWithEvents
if ($liveLabel -notmatch 'Everything') {
    Add-Failure "running task label should surface live install hints, got '$liveLabel'."
}

$profilesLabel = Get-WinMintSetupShellRuntimeTaskLabel -RuntimeStepName 'profiles'
if ($profilesLabel -ne 'Validate agent profile') {
    Add-Failure "profiles task label should come from catalog ShellLabel, got '$profilesLabel'."
}

$packageManagersLabel = Get-WinMintSetupShellRuntimeTaskLabel -RuntimeStepName 'package-managers'
if ($packageManagersLabel -ne 'Bootstrap winget and Scoop') {
    Add-Failure "package-managers task label should come from catalog ShellLabel, got '$packageManagersLabel'."
}

$toolsGroup = Resolve-WinMintSetupShellRuntimeGroupId -RuntimeStepName 'profiles'
if ($toolsGroup -ne 'tools') {
    Add-Failure "profiles runtime step should resolve to tools group, got '$toolsGroup'."
}

if ($failures.Count -gt 0) {
    throw "Provisioning projection contract tests failed with $($failures.Count) failure(s)."
}

Write-Host 'Provisioning projection contract tests passed.'
