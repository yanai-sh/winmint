#Requires -Version 7.6
# Dot-source the agent runtime stack at script scope.
# Set $agentRoot before loading. Optional: $IncludeAgentConsole = $true

if (-not $agentRoot) {
    throw 'Set $agentRoot to the WinMintAgent folder before dot-sourcing Agent.Load.ps1.'
}

foreach ($candidate in @(
        Join-Path $agentRoot 'WinMint.Runtime.Common.ps1'
        Join-Path (Split-Path -Parent $agentRoot) 'WinMint.Runtime.Common.ps1'
    )) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        . $candidate
        break
    }
}
if (-not (Get-Command Save-WinMintAtomicJson -ErrorAction SilentlyContinue)) {
    throw "WinMint.Runtime.Common.ps1 is missing for agent root '$agentRoot'."
}

. (Join-Path $agentRoot 'Agent.Context.ps1')
if ($IncludeAgentConsole) {
    . (Join-Path $agentRoot 'Agent.Console.ps1')
}
. (Join-Path $agentRoot 'Agent.State.ps1')
. (Join-Path $agentRoot 'Agent.Host.ps1')
. (Join-Path $agentRoot 'Agent.Install.ps1')
. (Join-Path $agentRoot 'Agent.Plan.ps1')
. (Join-Path $agentRoot 'Agent.Runtime.ps1')

function Initialize-TestAgentContext {
    param([Parameter(Mandatory)][hashtable]$Context)

    Set-WinMintAgentContext -Context $Context
}
