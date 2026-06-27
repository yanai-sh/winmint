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

function Sync-FirstLogonLegacyContext {
    param([Parameter(Mandatory)][hashtable]$Context)

    $logDir = [string]$Context.LogDir
    $payloadDir = [string]$Context.PayloadDir
    Set-Variable -Name logDir -Value $logDir -Scope Script -Force
    Set-Variable -Name payloadDir -Value $payloadDir -Scope Script -Force
    $script:WinMintFirstLogonMaxAttempts = [int]$Context.MaxAttempts
    $script:WinMintFirstLogonEntryPath = [string]$Context.EntryPath
    $script:WinMintElevated = [bool]$Context.Elevated
}

function Set-WinMintFirstLogonContext {
    param([Parameter(Mandatory)][hashtable]$Context)

    $script:FirstLogonContext = $Context
    Sync-FirstLogonLegacyContext -Context $Context
}

function Get-WinMintFirstLogonContext {
    if ($script:FirstLogonContext) { return $script:FirstLogonContext }
    throw 'WinMint FirstLogon context is not initialized.'
}

function Set-WinMintFirstLogonContextElevated {
    param([bool]$Elevated)

    $context = Get-WinMintFirstLogonContext
    $context.Elevated = [bool]$Elevated
    Set-WinMintFirstLogonContext -Context $context
}
