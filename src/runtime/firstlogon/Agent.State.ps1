#Requires -Version 7.6

$runtimeStateScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'WinMint.RuntimeState.ps1'
if (Test-Path -LiteralPath $runtimeStateScript -PathType Leaf) {
    . $runtimeStateScript
}

function Read-AgentJson {
    param([string]$Path, [object]$Fallback)
    Read-WinMintJsonFile -Path $Path -Fallback $Fallback -OnError {
        Write-AgentLog "JSON read failed: $Path :: $($_.Exception.Message)"
    }
}

function Save-AgentState {
    param([object]$State)
    $ctx = Get-WinMintAgentContext
    Save-WinMintAtomicJson -Path $ctx.StatePath -Data $State -Depth 12 -RemoveDestinationFirst
    # Splash status projection is best-effort: never fail agent modules if RuntimeState is missing.
    if (-not (Get-Command Import-WinMintRuntimeStateModule -ErrorAction SilentlyContinue)) {
        $runtimeStateScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'WinMint.RuntimeState.ps1'
        if (Test-Path -LiteralPath $runtimeStateScript -PathType Leaf) {
            . $runtimeStateScript
        }
    }
    if (Get-Command Import-WinMintRuntimeStateModule -ErrorAction SilentlyContinue) {
        Import-WinMintRuntimeStateModule
    }
    if (Get-Command Write-WinMintRuntimeState -ErrorAction SilentlyContinue) {
        Write-WinMintRuntimeState -Agent (New-WinMintRuntimeStateAgentDisplay -AgentState $State)
    }
}

function Set-AgentStateValue {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Name,
        $Value
    )
    if ($State -is [hashtable]) {
        $State[$Name] = $Value
        return
    }
    $prop = $State.PSObject.Properties[$Name]
    if ($prop) {
        $prop.Value = $Value
        return
    }
    Add-Member -InputObject $State -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Get-AgentStepAttempts {
    param([object]$Step)
    if (-not $Step) { return 0 }
    if ($Step -is [hashtable] -and $Step.ContainsKey('attempts')) { return [int]$Step.attempts }
    $prop = $Step.PSObject.Properties['attempts']
    if ($prop) { return [int]$prop.Value }
    return 0
}

function Test-WinMintAgentStateStepOk {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][string]$Key
    )

    if (-not $State.steps.ContainsKey($Key)) { return $false }
    return ([string]$State.steps[$Key].status -eq 'ok')
}

function Assert-WinMintAgentStateStepsOk {
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][string[]]$Keys,
        [Parameter(Mandatory)][string]$Context
    )

    $missing = [System.Collections.Generic.List[string]]::new()
    $notOk = [System.Collections.Generic.List[string]]::new()

    foreach ($key in @($Keys)) {
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        if (-not $State.steps.ContainsKey($key)) {
            $missing.Add($key) | Out-Null
            continue
        }

        $step = $State.steps[$key]
        $status = [string]$step.status
        if ($status -eq 'ok') { continue }

        $reason = if ($step -is [hashtable] -and $step.ContainsKey('error') -and -not [string]::IsNullOrWhiteSpace([string]$step.error)) {
            [string]$step.error
        }
        elseif ($step -is [hashtable] -and $step.ContainsKey('reason') -and -not [string]::IsNullOrWhiteSpace([string]$step.reason)) {
            [string]$step.reason
        }
        elseif ($step.PSObject.Properties['error'] -and -not [string]::IsNullOrWhiteSpace([string]$step.error)) {
            [string]$step.error
        }
        elseif ($step.PSObject.Properties['reason'] -and -not [string]::IsNullOrWhiteSpace([string]$step.reason)) {
            [string]$step.reason
        }
        else {
            $status
        }
        $notOk.Add("$key=$reason") | Out-Null
    }

    if (($missing.Count -eq 0) -and ($notOk.Count -eq 0)) { return }

    $parts = [System.Collections.Generic.List[string]]::new()
    if ($missing.Count -gt 0) { $parts.Add("missing: $($missing -join ', ')") | Out-Null }
    if ($notOk.Count -gt 0) { $parts.Add("not ok: $($notOk -join ', ')") | Out-Null }
    throw "$Context did not complete required state step(s): $($parts -join '; ')"
}
