#Requires -Version 7.6
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'src\runtime\setup\WinMint.RuntimeState.ps1')

$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Message)
    if ([string]$Actual -ne [string]$Expected) {
        $failures.Add("$Message Expected '$Expected', got '$Actual'.") | Out-Null
    }
}

$hashtableState = @{
    run = @{ status = 'ok' }
    steps = @{
        'module:profiles' = @{ status = 'ok' }
        'module:wsl' = @{ status = 'skipped' }
        'module:editors' = @{ status = 'running' }
    }
}
$hashtableDisplay = New-WinMintRuntimeStateAgentDisplay -AgentState $hashtableState
Assert-Equal -Actual $hashtableDisplay.runStatus -Expected 'ok' -Message 'Hashtable runStatus'
Assert-Equal -Actual $hashtableDisplay.completedSteps -Expected 2 -Message 'Hashtable completedSteps'
Assert-Equal -Actual $hashtableDisplay.totalSteps -Expected 3 -Message 'Hashtable totalSteps'
Assert-Equal -Actual $hashtableDisplay.currentStep -Expected 'module:editors' -Message 'Hashtable currentStep'

$psObjectState = [pscustomobject]@{
    run = [pscustomobject]@{ status = 'ok' }
    steps = [pscustomobject]@{
        'module:profiles' = [pscustomobject]@{ status = 'ok' }
    }
}
$psObjectDisplay = New-WinMintRuntimeStateAgentDisplay -AgentState $psObjectState
Assert-Equal -Actual $psObjectDisplay.runStatus -Expected 'ok' -Message 'PSCustomObject runStatus'
Assert-Equal -Actual $psObjectDisplay.completedSteps -Expected 1 -Message 'PSCustomObject completedSteps'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure }
    exit 1
}

Write-Host 'Runtime state agent display contract: OK'
exit 0
