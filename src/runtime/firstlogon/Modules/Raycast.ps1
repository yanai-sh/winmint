#Requires -Version 7.3

function Invoke-WinMintAgentRaycastBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    [void]$AgentProfile

    Install-AgentManifestTool -ToolId 'raycast' -State $State

    [pscustomobject]@{
        Id      = 'raycast'
        Status  = 'ok'
        Message = 'Raycast installed.'
    }
}
