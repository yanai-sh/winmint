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
        Message = 'Reserved for explicit user Git setup. If FirstLogon ever requires Git, use MinGit only; do not install full Git for Windows/Git Bash by default.'
    }
}
