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
