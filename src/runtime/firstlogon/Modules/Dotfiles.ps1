#Requires -Version 7.6

function Invoke-WinMintAgentDotfileBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    [void]$AgentProfile
    [void]$State
    [pscustomobject]@{
        Id      = 'dotfiles'
        Status  = 'scaffolded'
        Message = 'Reserved for cloning a dotfiles repository and running its installer.'
    }
}

