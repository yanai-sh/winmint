#Requires -Version 7.3
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

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
    )

    if ([string]$Actual -ne [string]$Expected) {
        Add-Failure "$Message Expected '$Expected', got '$Actual'."
    }
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) { Add-Failure $Message }
}

. (Join-Path $root 'src\runtime\setup\FirstLogon.Transaction.ps1')

$plan = @(New-WinMintFirstLogonTransactionPlan -AgentMode Console)
$expectedOrder = @(
    'prepare-host',
    'persist-retry-autologon',
    'restore-visible-user-posture',
    'apply-live-user-defaults',
    'launch-agent',
    'finalize-user-shell',
    'finalize-success',
    'finalize-recovery'
)

Assert-Equal (@($plan | Sort-Object Order | ForEach-Object { $_.Id }) -join ',') ($expectedOrder -join ',') 'FirstLogon transaction plan should preserve phase order.'

$restore = $plan | Where-Object { $_.Id -eq 'restore-visible-user-posture' } | Select-Object -First 1
$defaults = $plan | Where-Object { $_.Id -eq 'apply-live-user-defaults' } | Select-Object -First 1
$agent = $plan | Where-Object { $_.Id -eq 'launch-agent' } | Select-Object -First 1
$shell = $plan | Where-Object { $_.Id -eq 'finalize-user-shell' } | Select-Object -First 1
$success = $plan | Where-Object { $_.Id -eq 'finalize-success' } | Select-Object -First 1
$recovery = $plan | Where-Object { $_.Id -eq 'finalize-recovery' } | Select-Object -First 1

Assert-True ($restore.Order -lt $defaults.Order) 'DMA visible-posture restore should run before live-user defaults and cleanup.'
Assert-True (@($restore.Functions) -contains 'Restore-WinMintDmaRegionalDefaults') 'Visible-posture restore step should name DMA restore.'
Assert-True (@($defaults.Functions) -contains 'Invoke-WinMintFirstLogonOneDriveRemoval') 'Live-user defaults step should include OneDrive cleanup after restore.'
Assert-True ($agent.Order -lt $shell.Order) 'Agent launch should run before final terminal profile and Start pin finalization.'
Assert-True ($shell.Order -lt $success.Order) 'User-shell finalization should happen before success cleanup.'
Assert-Equal $agent.FailurePolicy 'blocking' 'Agent launch should be the blocking transaction step.'
Assert-Equal $success.Condition 'agentExitCode == 0' 'Success cleanup should be gated on successful agent exit.'
Assert-Equal $recovery.Condition 'agentExitCode != 0' 'Recovery handling should be gated on failed/incomplete agent exit.'
Assert-True (@($success.Functions) -contains 'Remove-WinMintResidualPayload') 'Residual payload cleanup should be success-only transaction work.'

if ($failures.Count -gt 0) {
    throw "FirstLogon transaction plan tests failed with $($failures.Count) failure(s)."
}

Write-Host 'FirstLogon transaction plan tests passed.'
