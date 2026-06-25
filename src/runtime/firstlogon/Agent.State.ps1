#Requires -Version 7.6

function Read-AgentJson {
    param([string]$Path, [object]$Fallback)
    try {
        if (Test-Path -LiteralPath $Path) {
            return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    } catch {
        Write-AgentLog "JSON read failed: $Path :: $($_.Exception.Message)"
    }
    return $Fallback
}

function Save-AgentState {
    param([object]$State)
    $json = $State | ConvertTo-Json -Depth 12
    $tmp = "$statePath.tmp"
    $json | Set-Content -LiteralPath $tmp -Encoding UTF8
    $null = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
    # Move-Item -Force does NOT reliably replace an existing file on Windows - it throws
    # "Cannot create a file when that file already exists", so every state update after the
    # first froze state.json. Remove the destination first so Move never hits the overwrite path.
    if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force }
    Move-Item -LiteralPath $tmp -Destination $statePath -Force
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
