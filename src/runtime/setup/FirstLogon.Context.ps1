#Requires -Version 5.1

function New-WinMintFirstLogonContext {
    param(
        [Parameter(Mandatory)][hashtable]$Spec
    )

    foreach ($name in @('LogDir', 'PayloadDir', 'EntryPath', 'MaxAttempts')) {
        if (-not $Spec.ContainsKey($name)) {
            throw "WinMint FirstLogon context missing required key '$name'."
        }
    }

    return @{
        LogDir = [string]$Spec.LogDir
        PayloadDir = [string]$Spec.PayloadDir
        EntryPath = [string]$Spec.EntryPath
        MaxAttempts = [int]$Spec.MaxAttempts
        Elevated = if ($Spec.ContainsKey('Elevated')) { [bool]$Spec.Elevated } else { $false }
        SetupScriptRoot = if ($Spec.ContainsKey('SetupScriptRoot')) { [string]$Spec.SetupScriptRoot } else { '' }
    }
}

function Set-WinMintFirstLogonContext {
    param([Parameter(Mandatory)][hashtable]$Context)

    $script:FirstLogonContext = $Context
}

function Get-WinMintFirstLogonContext {
    if ($script:FirstLogonContext) { return $script:FirstLogonContext }
    throw 'WinMint FirstLogon context is not initialized.'
}

function Set-WinMintFirstLogonContextElevated {
    param([bool]$Elevated)

    $context = Get-WinMintFirstLogonContext
    $context.Elevated = [bool]$Elevated
    $script:FirstLogonContext = $context
}

function Set-WinMintFirstLogonContextAgentMode {
    param([string]$AgentMode)

    $context = Get-WinMintFirstLogonContext
    $context.AgentMode = [string]$AgentMode
    $script:FirstLogonContext = $context
}
