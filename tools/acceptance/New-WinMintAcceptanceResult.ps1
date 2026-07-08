#Requires -Version 7.6

function New-WinMintAcceptanceSignalResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][bool]$Ok,
        [Parameter(Mandatory)][ValidateSet('plumbing', 'evidence')]
        [string]$Severity,
        [string]$Message = ''
    )

    [ordered]@{
        id = $Id
        ok = $Ok
        severity = $Severity
        message = [string]$Message
    }
}

function Complete-WinMintAcceptanceResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Result,
        [AllowEmptyCollection()][object[]]$Signals = @(),
        [ValidateSet('Smoke', 'Full', 'Auto', 'Hardware')]
        [string]$AcceptanceTier = 'Smoke'
    )

    $plumbingFails = [System.Collections.Generic.List[string]]::new()
    $evidenceFails = [System.Collections.Generic.List[string]]::new()
    foreach ($signal in @($Signals)) {
        if ($signal.ok) { continue }
        $label = if ([string]$signal.message) { "$($signal.id): $($signal.message)" } else { [string]$signal.id }
        if ($signal.severity -eq 'plumbing') { $plumbingFails.Add($label) | Out-Null }
        else { $evidenceFails.Add($label) | Out-Null }
    }

    if ($Result.PSObject.Properties['signalChecks']) {
        $existing = $Result.signalChecks
        foreach ($f in @($existing.plumbingFailures)) {
            if ($plumbingFails -notcontains $f) { $plumbingFails.Add([string]$f) | Out-Null }
        }
        foreach ($f in @($existing.evidenceFailures)) {
            if ($evidenceFails -notcontains $f) { $evidenceFails.Add([string]$f) | Out-Null }
        }
    }

    $plumbingPass = ($plumbingFails.Count -eq 0)
    if ($Result.PSObject.Properties['reachable']) {
        $plumbingPass = $plumbingPass -and [bool]$Result.reachable
    }
    if ($Result.firstLogon) {
        $plumbingPass = $plumbingPass -and ([string]$Result.firstLogon.status -eq 'ok')
    }

    $evidencePass = ($evidenceFails.Count -eq 0)
    $tier = if ($AcceptanceTier) { $AcceptanceTier } else { [string]$Result.acceptanceTier }
    $passed = if ($tier -eq 'Smoke') { $plumbingPass } elseif ($tier -eq 'Hardware') { $plumbingPass -and $evidencePass } else { ($plumbingPass -and $evidencePass) }

    $Result.schemaVersion = 1
    if (-not $Result.PSObject.Properties['acceptanceMode']) {
        $Result.acceptanceMode = if ($Result.machineId) { 'hardware' } else { 'vm' }
    }
    $Result.acceptanceTier = $tier
    $Result.plumbingVerdict = if ($plumbingPass) { 'pass' } else { 'fail' }
    $Result.evidenceVerdict = if ($evidencePass) { 'pass' } else { 'fail' }
    $Result.signalChecks = [ordered]@{
        plumbingOk = $plumbingPass
        evidenceOk = $evidencePass
        signals = @($Signals)
        plumbingFailures = @($plumbingFails)
        evidenceFailures = @($evidenceFails)
        failures = @($plumbingFails + $evidenceFails)
    }
    $Result.verdict = if ($passed) { 'pass' } else { 'fail' }
    if (-not $Result.PSObject.Properties['finishedAt'] -or [string]::IsNullOrWhiteSpace([string]$Result.finishedAt)) {
        $Result.finishedAt = (Get-Date).ToString('o')
    }
    return $Result
}

function Write-WinMintAcceptanceResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][string]$Path
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    ($Result | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $Path -Encoding UTF8
}
