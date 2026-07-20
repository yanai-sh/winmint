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
. (Join-Path $setupRoot 'WinMint.Diagnostics.ps1')
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
if ($locked.stageId -ne 'ready') {
    Add-Failure "locked stageId expected 'ready', got '$($locked.stageId)'."
}
if ($locked.taskLabel -ne 'Getting things ready') {
    Add-Failure "locked taskLabel expected 'Getting things ready', got '$($locked.taskLabel)'."
}
if ($locked.progressMode -ne 'indeterminate') {
    Add-Failure "locked stage progressMode expected indeterminate, got '$($locked.progressMode)'."
}
if ($locked.PSObject.Properties['steps']) {
    Add-Failure 'status projection must not emit steps[].'
}

$region = Get-WinMintProvisioningProjection -Control $control -AgentState $agentState -AgentProfile $agentProfile -LogDir $logDir -PreAgentStage 'region'
if ($region.stageId -ne 'ready') {
    Add-Failure "region stageId expected 'ready', got '$($region.stageId)'."
}
if ($region.progressMode -ne 'indeterminate') {
    Add-Failure "region stage progressMode expected indeterminate before agent, got '$($region.progressMode)'."
}

$finishing = Get-WinMintProvisioningProjection -Control (@{ phase = 'finishing'; profileName = 'Projection Test'; startedAt = (Get-Date).ToString('o') }) `
    -AgentState $agentState -AgentProfile $agentProfile -LogDir $logDir
if ($finishing.stageId -ne 'finish') {
    Add-Failure "finishing stageId expected 'finish', got '$($finishing.stageId)'."
}
if ($finishing.taskLabel -ne 'Finishing up') {
    Add-Failure "finishing taskLabel expected 'Finishing up', got '$($finishing.taskLabel)'."
}
if ($finishing.progressMode -ne 'indeterminate') {
    Add-Failure "finishing progressMode expected indeterminate, got '$($finishing.progressMode)'."
}

$complete = Get-WinMintProvisioningProjection -Control (@{ phase = 'complete'; profileName = 'Projection Test'; startedAt = (Get-Date).ToString('o') }) `
    -AgentState $agentState -AgentProfile $agentProfile -LogDir $logDir
if ($complete.taskLabel -ne "You're all set") {
    Add-Failure "complete taskLabel expected You're all set, got '$($complete.taskLabel)'."
}

$eventLog = Join-Path $logDir 'WinMintAgent-events.jsonl'
@(
    '{"time":"2026-01-01T00:00:00+00:00","type":"install","status":"running","message":"Installing mingit via Scoop for arm64."}'
    '{"time":"2026-01-01T00:00:01+00:00","type":"command","status":"running","message":"Running winget.exe."}'
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
if ($liveHint -notmatch 'MinGit|mingit') {
    Add-Failure "event log hint should prefer install over generic winget.exe, got '$liveHint'."
}
if ($liveHint -match '(?i)Running winget|Scoop|winget') {
    Add-Failure "event log hint must strip package-manager brands / generic Running.exe, got '$liveHint'."
}
$liveLabel = Resolve-WinMintSetupShellRunningTaskLabel `
    -RuntimeStepName 'package-managers' `
    -Phase 'running' `
    -FallbackLabel 'Bootstrap winget and Scoop' `
    -ProfileDisplayName 'Projection Test' `
    -AgentState $agentWithEvents
if ($liveLabel -notmatch 'MinGit|mingit|Preparing') {
    Add-Failure "running task label should surface live install hints, got '$liveLabel'."
}

$appsProjection = Get-WinMintProvisioningProjection `
    -Control (@{ phase = 'running'; profileName = 'Projection Test'; startedAt = (Get-Date).ToString('o'); preAgentStage = 'agent' }) `
    -AgentState $agentWithEvents `
    -AgentProfile $agentProfile `
    -LogDir $logDir `
    -PreAgentStage 'agent'
if ($appsProjection.stageId -ne 'ready') {
    Add-Failure "package-managers should map to ready stage, got '$($appsProjection.stageId)'."
}

$profilesLabel = Get-WinMintSetupShellRuntimeTaskLabel -RuntimeStepName 'profiles'
if ($profilesLabel -ne 'Validate agent profile') {
    Add-Failure "profiles task label should come from catalog ShellLabel, got '$profilesLabel'."
}

$toolsGroup = Resolve-WinMintSetupShellRuntimeGroupId -RuntimeStepName 'profiles'
if ($toolsGroup -ne 'ready') {
    Add-Failure "profiles runtime step should resolve to ready stage, got '$toolsGroup'."
}

$stripped = Format-WinMintSetupShellSplashDetail -Text 'Installing Cursor with winget'
if ($stripped -ne 'Installing Cursor') {
    Add-Failure "brand strip should yield 'Installing Cursor', got '$stripped'."
}

if ($failures.Count -gt 0) {
    throw "Provisioning projection contract tests failed with $($failures.Count) failure(s)."
}

Write-Host 'Provisioning projection contract tests passed.'
