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

function Test-WinMintAcceptanceResultHasProperty {
    param($Object, [string]$Name)

    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return [bool]$Object.PSObject.Properties[$Name]
}

function Get-WinMintAcceptanceResultProperty {
    param($Object, [string]$Name)

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    if ($Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
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

    if (Test-WinMintAcceptanceResultHasProperty -Object $Result -Name 'signalChecks') {
        $existing = Get-WinMintAcceptanceResultProperty -Object $Result -Name 'signalChecks'
        foreach ($f in @($existing.plumbingFailures)) {
            if ($plumbingFails -notcontains $f) { $plumbingFails.Add([string]$f) | Out-Null }
        }
        foreach ($f in @($existing.evidenceFailures)) {
            if ($evidenceFails -notcontains $f) { $evidenceFails.Add([string]$f) | Out-Null }
        }
    }

    $plumbingPass = ($plumbingFails.Count -eq 0)
    if (Test-WinMintAcceptanceResultHasProperty -Object $Result -Name 'reachable') {
        $plumbingPass = $plumbingPass -and [bool](Get-WinMintAcceptanceResultProperty -Object $Result -Name 'reachable')
    }
    $firstLogon = Get-WinMintAcceptanceResultProperty -Object $Result -Name 'firstLogon'
    if ($firstLogon) {
        $firstLogonStatus = if ($firstLogon -is [System.Collections.IDictionary]) { [string]$firstLogon['status'] } else { [string]$firstLogon.status }
        $plumbingPass = $plumbingPass -and ($firstLogonStatus -eq 'ok')
    }

    $evidencePass = ($evidenceFails.Count -eq 0)
    $tier = if ($AcceptanceTier) { $AcceptanceTier } else { [string]$Result.acceptanceTier }
    $passed = if ($tier -eq 'Smoke') { $plumbingPass } elseif ($tier -eq 'Hardware') { $plumbingPass -and $evidencePass } else { ($plumbingPass -and $evidencePass) }

    $Result.schemaVersion = 1
    if (-not (Test-WinMintAcceptanceResultHasProperty -Object $Result -Name 'acceptanceMode')) {
        $machineId = Get-WinMintAcceptanceResultProperty -Object $Result -Name 'machineId'
        if ($Result -is [System.Collections.IDictionary]) {
            $Result['acceptanceMode'] = if ($machineId) { 'hardware' } else { 'vm' }
        }
        else {
            $Result | Add-Member -NotePropertyName acceptanceMode -NotePropertyValue $(if ($machineId) { 'hardware' } else { 'vm' }) -Force
        }
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
    $finishedAt = Get-WinMintAcceptanceResultProperty -Object $Result -Name 'finishedAt'
    if ([string]::IsNullOrWhiteSpace([string]$finishedAt)) {
        if ($Result -is [System.Collections.IDictionary]) { $Result['finishedAt'] = (Get-Date).ToString('o') }
        else { $Result.finishedAt = (Get-Date).ToString('o') }
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
