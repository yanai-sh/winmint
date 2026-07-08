#Requires -Version 7.6
<#
.SYNOPSIS
    Validate that a WinMint profile is suitable for Hyper-V testing.

.DESCRIPTION
    Hyper-V testing expects a Windows 11 Pro build so Enhanced Session is
    available. The install must also be fully unattended, which means a local
    account needs an explicit password. This script checks those invariants
    before a build/test loop spends time generating an ISO that cannot satisfy
    the VM harness.

    -Tier Full validates the release-gate profile (browsers, editors, WSL distros, Nilesoft).
    -Tier Smoke validates the lean plumbing profile (standard desktop, WSL baseline only).

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Test-WinMintHyperVProfile.ps1 -ProfilePath .\tests\profiles\hyper-v-install-arm64.json

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Test-WinMintHyperVProfile.ps1 -ProfilePath .\tests\profiles\hyper-v-smoke-arm64.json -Tier Smoke
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProfilePath,
    [ValidateSet('Full', 'Smoke')]
    [string]$Tier = 'Full'
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'WinMint-VmAcceptanceProfile.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Import-Module (Join-Path $repoRoot 'src\runtime\modules\WinMint.Profile\WinMint.Profile.psd1') -Force

if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
    throw "Profile not found: $ProfilePath"
}

$profile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json

$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
}

$profileName = [string]$profile.profileName
$expectedProfileName = if ($Tier -eq 'Smoke') { 'Hyper-V Smoke' } else { 'Hyper-V Test' }
if ($profileName -ne $expectedProfileName) {
    Add-Failure "Hyper-V $Tier profiles must set profileName to '$expectedProfileName'; got '$profileName'."
}
if (-not (Test-WinMintVmAcceptanceDiagnosticsPreset -Profile $profile -Tier $Tier)) {
    Add-Failure "Hyper-V $Tier profiles must include the VM acceptance diagnostics preset (retainFirstLogonArtifacts, provisioningShellDwellMs, wslRuntimeValidation)."
}

$edition = [string]$profile.target.edition
if ($edition -ne 'Windows 11 Pro') {
    Add-Failure "Hyper-V test profiles must target Windows 11 Pro; got '$edition'."
}

$productKey = [string]$profile.target.productKey
if ($productKey -ne 'VK7JG-NPHTM-C97JM-9MPGT-3V66T') {
    Add-Failure 'Hyper-V test profiles must use the Pro generic key VK7JG-NPHTM-C97JM-9MPGT-3V66T.'
}

$accountMode = [string]$profile.identity.accountMode
if ($accountMode -ne 'Local') {
    Add-Failure "Hyper-V test profiles must use a local account for unattended installs; got '$accountMode'."
}

$computerName = [string]$profile.identity.computerName
if ([string]::IsNullOrWhiteSpace($computerName)) {
    Add-Failure 'Hyper-V test profiles must set an explicit computer name.'
}

if (-not [bool]$profile.identity.autoLogon) {
    Add-Failure 'Hyper-V test profiles must enable autoLogon so the guest is reachable after setup.'
}

$password = [string]$profile.identity.password
if ([string]::IsNullOrWhiteSpace($password)) {
    Add-Failure 'Hyper-V test profiles must set a local-account password. Windows 11 unattended local-account OOBE requires it.'
}

if (-not [bool]$profile.identity.passwordSet) {
    Add-Failure 'Hyper-V test profiles must mark the password as set.'
}

if (-not [bool]$profile.identity.passwordIncluded) {
    Add-Failure 'Hyper-V test profiles must include the password in the authored profile so the VM install remains unattended.'
}

if ([string]$profile.features.launcher -ne 'None') {
    Add-Failure 'Hyper-V test profiles must not select a launcher.'
}

if ($Tier -eq 'Smoke') {
    if (@($profile.development.wsl.distros).Count -gt 0) {
        Add-Failure 'Hyper-V Smoke profiles must not select WSL distros.'
    }
    if (@($profile.development.browsers).Count -gt 0) {
        Add-Failure 'Hyper-V Smoke profiles must not select browsers.'
    }
    if (@($profile.development.editors).Count -gt 0) {
        Add-Failure 'Hyper-V Smoke profiles must not select editors.'
    }
    $layers = @($profile.desktop.layers)
    if ($layers.Count -ne 1 -or $layers[0] -ne 'standard') {
        Add-Failure 'Hyper-V Smoke profiles must use the standard desktop layer only.'
    }
}
else {
    $wslDistros = @($profile.development.wsl.distros)
    foreach ($expectedDistro in @('Ubuntu', 'NixOS-WSL')) {
        if ($wslDistros -notcontains $expectedDistro) {
            Add-Failure "Hyper-V Full profiles must select $expectedDistro."
        }
    }
    if ($wslDistros.Count -ne 2) {
        Add-Failure 'Hyper-V Full profiles should select exactly Ubuntu and NixOS-WSL so official and community WSL install paths are easy to verify.'
    }
    if (@($profile.desktop.layers) -notcontains 'nilesoft') {
        Add-Failure 'Hyper-V Full profiles must select the Nilesoft shell layer.'
    }
}

try {
    Assert-WinMintBuildProfile -BuildProfile $profile
}
catch {
    Add-Failure "Build profile validation failed: $($_.Exception.Message)"
}

if ($failures.Count -gt 0) {
    throw ($failures -join [Environment]::NewLine)
}

Write-Host "Hyper-V profile is ready ($Tier): $ProfilePath"
