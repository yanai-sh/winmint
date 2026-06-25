#Requires -Version 7.6
# Dot-source the agent runtime stack at script scope.
# Set $agentRoot before loading. Optional: $IncludeAgentConsole = $true

if (-not $agentRoot) {
    throw 'Set $agentRoot to the WinMintAgent folder before dot-sourcing Agent.Load.ps1.'
}

if ($IncludeAgentConsole) {
    . (Join-Path $agentRoot 'Agent.Console.ps1')
}
. (Join-Path $agentRoot 'Agent.State.ps1')
. (Join-Path $agentRoot 'Agent.Host.ps1')
. (Join-Path $agentRoot 'Agent.Install.ps1')
. (Join-Path $agentRoot 'Agent.Plan.ps1')
. (Join-Path $agentRoot 'Agent.Runtime.ps1')
