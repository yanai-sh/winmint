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
    -Tier Smoke validates either the lean plumbing profile (Hyper-V Smoke) or the
      SL7-shaped smoke profile (Hyper-V SL7 Smoke: Cursor/Zen/mocked Fedora; Edge kept + debloated).

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Test-WinMintHyperVProfile.ps1 -ProfilePath .\tests\profiles\hyper-v-install-arm64.json

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Test-WinMintHyperVProfile.ps1 -ProfilePath .\tests\profiles\hyper-v-smoke-arm64.json -Tier Smoke

.EXAMPLE
    pwsh -NoProfile -File .\tools\vm\Test-WinMintHyperVProfile.ps1 -ProfilePath .\tests\profiles\hyper-v-sl7-smoke-arm64.json -Tier Smoke
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
$isSl7Smoke = ($profileName -eq 'Hyper-V SL7 Smoke')
$expectedSmokeNames = @('Hyper-V Smoke', 'Hyper-V SL7 Smoke')
if ($Tier -eq 'Smoke') {
    if ($profileName -notin $expectedSmokeNames) {
        Add-Failure "Hyper-V Smoke profiles must set profileName to 'Hyper-V Smoke' or 'Hyper-V SL7 Smoke'; got '$profileName'."
    }
}
elseif ($profileName -ne 'Hyper-V Test') {
    Add-Failure "Hyper-V Full profiles must set profileName to 'Hyper-V Test'; got '$profileName'."
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
    $layers = @($profile.desktop.layers)
    if ($layers.Count -ne 1 -or $layers[0] -ne 'standard') {
        Add-Failure 'Hyper-V Smoke profiles must use the standard desktop layer only.'
    }
    if ($isSl7Smoke) {
        if (@($profile.development.editors) -notcontains 'cursor' -or @($profile.development.editors).Count -ne 1) {
            Add-Failure 'Hyper-V SL7 Smoke must select exactly the Cursor editor.'
        }
        if (@($profile.development.browsers) -notcontains 'zen-browser' -or @($profile.development.browsers).Count -ne 1) {
            Add-Failure 'Hyper-V SL7 Smoke must select exactly zen-browser.'
        }
        if (@($profile.development.wsl.distros) -notcontains 'FedoraLinux' -or @($profile.development.wsl.distros).Count -ne 1) {
            Add-Failure 'Hyper-V SL7 Smoke must select exactly FedoraLinux (mocked via wslRuntimeValidation=skip).'
        }
        if ([string]$profile.diagnostics.wslRuntimeValidation -ne 'skip') {
            Add-Failure 'Hyper-V SL7 Smoke must set diagnostics.wslRuntimeValidation=skip.'
        }
        if (-not [bool]$profile.keep.edge) {
            Add-Failure 'Hyper-V SL7 Smoke must keep.edge=true (Edge stays installed; debloat-only).'
        }
        if (-not [bool]$profile.features.phoneLink) {
            Add-Failure 'Hyper-V SL7 Smoke must enable features.phoneLink.'
        }
        if (-not [bool]$profile.features.liveInstallAudit) {
            Add-Failure 'Hyper-V SL7 Smoke must enable features.liveInstallAudit.'
        }
        if ([string]$profile.regional.userLocale -ne 'he-IL' -or [int]$profile.regional.homeLocationGeoId -ne 117) {
            Add-Failure 'Hyper-V SL7 Smoke must use Israel regional restore (userLocale he-IL, GeoID 117).'
        }
        if ([string]$profile.regional.uiLanguage -ne 'en-US') {
            Add-Failure 'Hyper-V SL7 Smoke must keep UI language en-US.'
        }
    }
    else {
        if (@($profile.development.wsl.distros).Count -gt 0) {
            Add-Failure 'Hyper-V Smoke (lean) profiles must not select WSL distros.'
        }
        if (@($profile.development.browsers).Count -gt 0) {
            Add-Failure 'Hyper-V Smoke (lean) profiles must not select browsers.'
        }
        if (@($profile.development.editors).Count -gt 0) {
            Add-Failure 'Hyper-V Smoke (lean) profiles must not select editors.'
        }
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
        Write-Warning 'Hyper-V Full profiles should select exactly Ubuntu and NixOS-WSL so official and community WSL install paths are easy to verify.'
    }
    if (@($profile.desktop.layers) -notcontains 'nilesoft') {
        Write-Warning 'Hyper-V Full profiles must select the Nilesoft shell layer.'
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
