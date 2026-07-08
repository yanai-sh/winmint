#Requires -Version 7.6

function New-WinMintAgentContext {
    param(
        [Parameter(Mandatory)][hashtable]$Spec
    )

    foreach ($name in @('AgentRoot', 'State', 'StatePath', 'AgentProfile', 'LogDir', 'EventLogPath', 'CommandLogDir')) {
        if (-not $Spec.ContainsKey($name)) {
            throw "WinMint agent context missing required key '$name'."
        }
    }

    $stateDir = if ($Spec.ContainsKey('StateDir') -and -not [string]::IsNullOrWhiteSpace([string]$Spec.StateDir)) {
        [string]$Spec.StateDir
    }
    else {
        Split-Path -Parent [string]$Spec.StatePath
    }

    return @{
        AgentRoot = [string]$Spec.AgentRoot
        State = $Spec.State
        StatePath = [string]$Spec.StatePath
        AgentProfile = $Spec.AgentProfile
        Manifest = if ($Spec.ContainsKey('Manifest')) { $Spec.Manifest } else { $null }
        Force = if ($Spec.ContainsKey('Force')) { [bool]$Spec.Force } else { $false }
        LogDir = [string]$Spec.LogDir
        EventLogPath = [string]$Spec.EventLogPath
        CommandLogDir = [string]$Spec.CommandLogDir
        StateDir = $stateDir
        ManifestPath = if ($Spec.ContainsKey('ManifestPath')) { [string]$Spec.ManifestPath } else { '' }
        TargetArchitecture = if ($Spec.ContainsKey('TargetArchitecture')) { [string]$Spec.TargetArchitecture } else { '' }
        Interactive = if ($Spec.ContainsKey('Interactive')) { [bool]$Spec.Interactive } else { $false }
        EmitProgressJson = if ($Spec.ContainsKey('EmitProgressJson')) { [bool]$Spec.EmitProgressJson } else { $false }
    }
}

function Set-WinMintAgentContext {
    param([Parameter(Mandatory)][hashtable]$Context)

    $script:AgentContext = $Context
}

function Get-WinMintAgentContext {
    if ($script:AgentContext) { return $script:AgentContext }
    throw 'WinMint agent context is not initialized.'
}
