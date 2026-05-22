#Requires -Version 7.3

function Invoke-WinMintAgentGitBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    [void]$AgentProfile
    [void]$State
    [pscustomobject]@{
        Id      = 'git'
        Status  = 'scaffolded'
        Message = 'Reserved for user.name, user.email, default branch, and credential helper setup.'
    }
}
