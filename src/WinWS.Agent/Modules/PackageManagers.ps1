#Requires -Version 7.3

function Invoke-WinWSAgentPackageManagerBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    [void]$AgentProfile
    [void]$State
    $winget = Wait-WingetPath
    if (-not $winget) { throw 'winget.exe not available after wait.' }

    [pscustomobject]@{
        Id      = 'package-managers'
        Status  = 'ok'
        Message = 'winget ready.'
    }
}
