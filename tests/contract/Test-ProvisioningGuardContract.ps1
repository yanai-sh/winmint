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

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) { Add-Failure $Message }
}

$guardText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\ProvisioningGuard.ps1') -Raw

foreach ($marker in @('guard-engage', 'guard-release', 'host-exit')) {
    Assert-True ($guardText -match "Write-WinMintProvisioningGuardLog[\s\S]{0,80}-Marker\s+'$marker'") "ProvisioningGuard.ps1 should log provisioning-lock:$marker marker."
}
Assert-True ($guardText -match 'Write-WinMintProvisioningGuardLog[\s\S]{0,80}-Marker\s+"host-start') 'ProvisioningGuard.ps1 should log provisioning-lock:host-start marker.'

foreach ($expected in @(
        'Enable-WinMintProvisioningGuard'
        'Stop-WinMintProvisioningHostResidual'
        'Start-WinMintProvisioningHost'
        'Wait-WinMintProvisioningHost'
        'Disable-WinMintProvisioningGuard'
        'DisableTaskSwitching'
    )) {
    Assert-True ($guardText -match [regex]::Escape($expected)) "ProvisioningGuard.ps1 should expose '$expected'."
}

Assert-True ($guardText -match 'Stop-WinMintSetupShellHostProcesses') 'Start-WinMintProvisioningHost should kill stale hosts without clearing an engaged guard.'
Assert-True ($guardText -match 'presenter=native') 'Start-WinMintProvisioningHost should log native presenter selection.'
Assert-True ($guardText -match 'function Start-WinMintProvisioningHostEarly') 'ProvisioningGuard should expose Start-WinMintProvisioningHostEarly for PreLock.'
Assert-True ($guardText -match 'AdoptIfRunning') 'Start-WinMintProvisioningHost should adopt a PreLock-started host.'
Assert-True ($guardText -match 'host-adopt') 'ProvisioningGuard should log host-adopt when reusing a live splash.'

$preLockText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\FirstLogon.PreLock.ps1') -Raw
Assert-True ($preLockText -match 'Start-WinMintProvisioningHostEarly') 'FirstLogon.PreLock.ps1 should start the provisioning splash early.'
Assert-True ($preLockText -match 'AppsUseLightTheme') 'FirstLogon.PreLock.ps1 should apply dark mode before the splash.'

$runtimeText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\FirstLogon.Runtime.ps1') -Raw
Assert-True ($runtimeText -match 'engage-provisioning-lock') 'FirstLogon runtime should wire engage-provisioning-lock.'
Assert-True ($runtimeText -match 'release-provisioning-lock') 'FirstLogon runtime should wire release-provisioning-lock.'
Assert-True ($runtimeText -match 'Resolve-WinMintProvisioningReleasePhase') 'Release step should derive terminal phase from agent outcome.'
Assert-True ($runtimeText -match 'AdoptIfRunning') 'engage-provisioning-lock should AdoptIfRunning the PreLock host.'

if ($failures.Count -gt 0) {
    throw "Provisioning guard contract tests failed with $($failures.Count) failure(s)."
}

Write-Host 'Provisioning guard contract tests passed.'
