#Requires -Version 7.6
# VM acceptance harness profile metadata — not loaded on installed systems.

function Get-WinMintVmAcceptanceProfileName {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Smoke', 'Full')]
        [string]$Tier
    )

    switch ($Tier) {
        'Smoke' { return 'Hyper-V Smoke' }
        default { return 'Hyper-V Test' }
    }
}

function Get-WinMintVmAcceptanceDiagnosticsPreset {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Smoke', 'Full')]
        [string]$Tier
    )

    $preset = [ordered]@{
        retainFirstLogonArtifacts = $true
        provisioningShellDwellMs  = 10000
        vmGuestBasicConsole       = $true
    }
    $preset.wslRuntimeValidation = if ($Tier -eq 'Smoke') { 'skip' } else { 'full' }
    return $preset
}

function Merge-WinMintVmAcceptanceDiagnosticsOverlay {
    param(
        [Parameter(Mandatory)]$Profile,
        [Parameter(Mandatory)]$Overlay
    )

    $merged = $Profile | ConvertTo-Json -Depth 24 | ConvertFrom-Json
    $merged | Add-Member -NotePropertyName diagnostics -NotePropertyValue (
        $Overlay | ConvertTo-Json -Depth 6 | ConvertFrom-Json
    ) -Force
    return $merged
}

function Set-WinMintVmAcceptanceProfileMetadata {
    param(
        [Parameter(Mandatory)]$Profile,
        [Parameter(Mandatory)]
        [ValidateSet('Smoke', 'Full')]
        [string]$Tier
    )

    $Profile.profileName = Get-WinMintVmAcceptanceProfileName -Tier $Tier
    $overlay = Get-WinMintVmAcceptanceDiagnosticsPreset -Tier $Tier
    return Merge-WinMintVmAcceptanceDiagnosticsOverlay -Profile $Profile -Overlay $overlay
}

function Test-WinMintVmAcceptanceDiagnosticsPreset {
    param(
        [Parameter(Mandatory)]$Profile,
        [Parameter(Mandatory)]
        [ValidateSet('Smoke', 'Full')]
        [string]$Tier
    )

    $expected = Get-WinMintVmAcceptanceDiagnosticsPreset -Tier $Tier
    $actual = $Profile.diagnostics
    if (-not $actual) { return $false }

    foreach ($name in @('retainFirstLogonArtifacts', 'provisioningShellDwellMs', 'wslRuntimeValidation', 'vmGuestBasicConsole')) {
        $expectedValue = [string]$expected.$name
        $actualValue = [string]$actual.$name
        # Allow any profile to mock WSL by explicitly opting into 'skip', even if the tier demands 'full'
        if ($name -eq 'wslRuntimeValidation' -and $actualValue -eq 'skip') { continue }
        if ($actualValue -ne $expectedValue) { return $false }
    }
    return $true
}

function Resolve-WinMintVmAcceptanceTierFromProfile {
    param([Parameter(Mandatory)]$ProfileJson)

    if ($ProfileJson.diagnostics) {
        $wslMode = [string]$ProfileJson.diagnostics.wslRuntimeValidation
        if ($wslMode -eq 'skip') { return 'Smoke' }
        if ($wslMode -eq 'full' -and [bool]$ProfileJson.diagnostics.retainFirstLogonArtifacts) {
            return 'Full'
        }
    }

    $profileName = [string]$ProfileJson.profileName
    if ($profileName -eq 'Hyper-V Smoke') { return 'Smoke' }
    if ($profileName -eq 'Hyper-V Test') { return 'Full' }
    return 'Auto'
}
