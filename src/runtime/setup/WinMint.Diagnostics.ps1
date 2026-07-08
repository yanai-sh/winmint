#Requires -Version 5.1

function Get-WinMintDiagnosticsBlock {
    param([Parameter(Mandatory)]$Source)

    if (-not $Source) { return $null }
    if (-not $Source.PSObject.Properties['diagnostics']) { return $null }
    return $Source.diagnostics
}

function Test-WinMintDiagnosticsFlag {
    param(
        [Parameter(Mandatory)]$Diagnostics,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Diagnostics) { return $false }
    if ($Diagnostics -is [System.Collections.IDictionary]) {
        return [bool]$Diagnostics[$Name]
    }
    if ($Diagnostics.PSObject.Properties[$Name]) {
        return [bool]$Diagnostics.$Name
    }
    return $false
}

function Get-WinMintDiagnosticsString {
    param(
        [Parameter(Mandatory)]$Diagnostics,
        [Parameter(Mandatory)][string]$Name,
        [string]$Default = ''
    )

    if (-not $Diagnostics) { return $Default }
    if ($Diagnostics -is [System.Collections.IDictionary] -and $Diagnostics.Contains($Name)) {
        return [string]$Diagnostics[$Name]
    }
    if ($Diagnostics.PSObject.Properties[$Name]) {
        return [string]$Diagnostics.$Name
    }
    return $Default
}

function Get-WinMintDiagnosticsInt {
    param(
        [Parameter(Mandatory)]$Diagnostics,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Diagnostics) { return 0 }
    if ($Diagnostics -is [System.Collections.IDictionary] -and $Diagnostics.Contains($Name)) {
        return [int]$Diagnostics[$Name]
    }
    if ($Diagnostics.PSObject.Properties[$Name]) {
        return [int]$Diagnostics.$Name
    }
    return 0
}

function Test-WinMintSetupRetainFirstLogonArtifacts {
    $setupProfile = Read-WinMintFirstLogonSetupProfile
    $diagnostics = Get-WinMintDiagnosticsBlock -Source $setupProfile
    return Test-WinMintDiagnosticsFlag -Diagnostics $diagnostics -Name 'retainFirstLogonArtifacts'
}

function Get-WinMintSetupProvisioningShellDwellOverrideMs {
    $setupProfile = Read-WinMintFirstLogonSetupProfile
    $diagnostics = Get-WinMintDiagnosticsBlock -Source $setupProfile
    $ms = Get-WinMintDiagnosticsInt -Diagnostics $diagnostics -Name 'provisioningShellDwellMs'
    if ($ms -gt 0) { return $ms }
    return $null
}

function Test-WinMintAgentWslRuntimeValidationSkipped {
    param([Parameter(Mandatory)]$AgentProfile)

    $diagnostics = Get-WinMintDiagnosticsBlock -Source $AgentProfile
    return (Get-WinMintDiagnosticsString -Diagnostics $diagnostics -Name 'wslRuntimeValidation' -Default 'full') -eq 'skip'
}

function Test-WinMintSetupVmGuestBasicConsole {
    $setupProfile = Read-WinMintFirstLogonSetupProfile
    $diagnostics = Get-WinMintDiagnosticsBlock -Source $setupProfile
    return Test-WinMintDiagnosticsFlag -Diagnostics $diagnostics -Name 'vmGuestBasicConsole'
}
