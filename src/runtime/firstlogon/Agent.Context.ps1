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

function Sync-AgentLegacyContext {
    param([Parameter(Mandatory)][hashtable]$Context)

    $script:agentRoot = [string]$Context.AgentRoot
    $script:state = $Context.State
    $script:State = $Context.State
    $script:agentProfile = $Context.AgentProfile
    $script:manifest = $Context.Manifest
    $script:Force = [bool]$Context.Force
    $script:logDir = [string]$Context.LogDir
    $script:statePath = [string]$Context.StatePath
    $script:eventLogPath = [string]$Context.EventLogPath
    $script:commandLogDir = [string]$Context.CommandLogDir
    $script:stateDir = [string]$Context.StateDir
    $script:InteractiveFirstLogon = [bool]$Context.Interactive
    $script:EmitProgressJson = [bool]$Context.EmitProgressJson
    if (-not [string]::IsNullOrWhiteSpace([string]$Context.TargetArchitecture)) {
        $script:AgentTargetArchitecture = [string]$Context.TargetArchitecture
    }
}

function Set-WinMintAgentContext {
    param([Parameter(Mandatory)][hashtable]$Context)

    $script:AgentContext = $Context
    Sync-AgentLegacyContext -Context $Context
}

function Get-WinMintAgentContext {
    if ($script:AgentContext) { return $script:AgentContext }
    throw 'WinMint agent context is not initialized.'
}
