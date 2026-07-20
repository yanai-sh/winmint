#Requires -Version 7.6
<#
.SYNOPSIS
    SetupComplete errors.log is hard plumbing; warnings.log is soft only.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-ScEvidenceFailure {
    param([string]$Message)
    $script:failures.Add($Message) | Out-Null
}

. (Join-Path $root 'tools\vm\lib\VmSetupCompleteEvidence.ps1')
. (Join-Path $root 'tools\acceptance\New-WinMintAcceptanceResult.ps1')

$fx = Join-Path ([System.IO.Path]::GetTempPath()) ("winmint-sc-ev-" + [guid]::NewGuid().ToString('n'))
$logs = Join-Path $fx 'ProgramData-Logs'
$null = New-Item -ItemType Directory -Path $logs -Force

try {
    # --- errors only → plumbing fail ---
    'hard failure line' | Set-Content -LiteralPath (Join-Path $logs 'SetupComplete_errors.log') -Encoding UTF8
    $errorsOnly = Test-WinMintVmSetupCompleteLogEvidence -EvidenceDir $fx
    if ($errorsOnly.plumbingOk) {
        Add-ScEvidenceFailure 'Non-empty SetupComplete_errors.log must fail plumbing.'
    }
    if ($errorsOnly.softWarnings.Count -ne 0) {
        Add-ScEvidenceFailure 'Errors-only fixture must not emit soft warnings.'
    }
    if (-not (@($errorsOnly.plumbingFailures) -match 'SetupComplete_errors\.log').Count) {
        Add-ScEvidenceFailure 'Plumbing failure text must mention SetupComplete_errors.log.'
    }

    # --- warnings only → plumbing pass + soft warning ---
    Remove-Item -LiteralPath (Join-Path $logs 'SetupComplete_errors.log') -Force -ErrorAction SilentlyContinue
    'soft warning line' | Set-Content -LiteralPath (Join-Path $logs 'SetupComplete_warnings.log') -Encoding UTF8
    $warnOnly = Test-WinMintVmSetupCompleteLogEvidence -EvidenceDir $fx
    if (-not $warnOnly.plumbingOk) {
        Add-ScEvidenceFailure 'Warnings-only fixture must pass plumbing.'
    }
    if ($warnOnly.softWarnings.Count -lt 1) {
        Add-ScEvidenceFailure 'Warnings-only fixture must surface softWarnings.'
    }
    if (-not (@($warnOnly.softWarnings) -match 'SetupComplete_warnings\.log').Count) {
        Add-ScEvidenceFailure 'Soft warning text must mention SetupComplete_warnings.log.'
    }

    # --- both → plumbing fail + soft warning ---
    'hard failure line' | Set-Content -LiteralPath (Join-Path $logs 'SetupComplete_errors.log') -Encoding UTF8
    $both = Test-WinMintVmSetupCompleteLogEvidence -EvidenceDir $fx
    if ($both.plumbingOk) {
        Add-ScEvidenceFailure 'Errors+warnings fixture must fail plumbing.'
    }
    if ($both.softWarnings.Count -lt 1) {
        Add-ScEvidenceFailure 'Errors+warnings fixture must still surface softWarnings.'
    }

    # --- empty → plumbing pass ---
    Remove-Item -LiteralPath (Join-Path $logs 'SetupComplete_errors.log') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $logs 'SetupComplete_warnings.log') -Force -ErrorAction SilentlyContinue
    $empty = Test-WinMintVmSetupCompleteLogEvidence -EvidenceDir $fx
    if (-not $empty.plumbingOk -or $empty.softWarnings.Count -ne 0) {
        Add-ScEvidenceFailure 'Empty SetupComplete logs must pass plumbing with no soft warnings.'
    }

    # --- Smoke verdict glue: soft warnings alone must not flip plumbingVerdict ---
    'soft warning line' | Set-Content -LiteralPath (Join-Path $logs 'SetupComplete_warnings.log') -Encoding UTF8
    $warnClassified = Test-WinMintVmSetupCompleteLogEvidence -EvidenceDir $fx
    $smokeResult = [ordered]@{
        acceptanceMode  = 'vm'
        acceptanceTier  = 'Smoke'
        startedAt       = (Get-Date).ToString('o')
        evidenceDir     = $fx
        reachable       = $true
        firstLogon      = @{ status = 'ok' }
        warnings        = @($warnClassified.softWarnings)
        reasons         = @()
    }
    # Soft warnings are recorded on the result, not as plumbing signals.
    $smokeResult = Complete-WinMintAcceptanceResult -Result $smokeResult -Signals @() -AcceptanceTier Smoke
    if ($smokeResult.plumbingVerdict -ne 'pass' -or $smokeResult.verdict -ne 'pass') {
        Add-ScEvidenceFailure "Smoke+soft-warnings-only must pass plumbing/verdict (got plumbing=$($smokeResult.plumbingVerdict) verdict=$($smokeResult.verdict))."
    }
    if (@($smokeResult.warnings).Count -lt 1) {
        Add-ScEvidenceFailure 'Smoke soft-warnings fixture must keep warnings on the acceptance result.'
    }

    # Hard errors as plumbing signals still fail Smoke.
    $hardSignals = @(
        New-WinMintAcceptanceSignalResult -Id 'vm.plumbing' -Ok $false -Severity plumbing -Message 'SetupComplete_errors.log is non-empty: hard'
    )
    $hardResult = Complete-WinMintAcceptanceResult -Result ([ordered]@{
            acceptanceMode = 'vm'
            acceptanceTier = 'Smoke'
            startedAt      = (Get-Date).ToString('o')
            evidenceDir    = $fx
            reachable      = $true
            firstLogon     = @{ status = 'ok' }
            warnings       = @($warnClassified.softWarnings)
            reasons        = @()
        }) -Signals $hardSignals -AcceptanceTier Smoke
    if ($hardResult.plumbingVerdict -ne 'fail' -or $hardResult.verdict -ne 'fail') {
        Add-ScEvidenceFailure 'Smoke+SetupComplete_errors plumbing signal must fail plumbing/verdict.'
    }
}
finally {
    Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue
}

$acceptance = Get-Content -LiteralPath (Join-Path $root 'tools\vm\Invoke-WinMintVmAcceptance.ps1') -Raw
if ($acceptance -notmatch 'Test-WinMintVmSetupCompleteLogEvidence') {
    Add-ScEvidenceFailure 'Invoke-WinMintVmAcceptance.ps1 must classify SetupComplete logs via Test-WinMintVmSetupCompleteLogEvidence.'
}
if ($acceptance -notmatch 'vm\.autologon') {
    Add-ScEvidenceFailure 'Invoke-WinMintVmAcceptance.ps1 must write vm.autologon plumbing signal on defaultuser0 hang.'
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}

Write-Host 'VM SetupComplete log evidence contract: OK'
exit 0
