#requires -Version 7.6
# Smoke fail-fast ordering: pins + S5 assert before staging clear (no live ISO / Hyper-V).
# Pin green/fail coverage lives in Test-ApplyEvidence.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$smoke = Get-Content -LiteralPath (Join-Path $repo 'tools\vm\Invoke-Smoke.ps1') -Raw -Encoding utf8
$assertAt = $smoke.IndexOf('Assert-ApplyEvidence (offline digests / pins) before Hyper-V')
$pinAt = $smoke.IndexOf('Get-WinMintDebloatPinsFromStages -StagesPath')
$clearAt = $smoke.IndexOf('Clear-WinMintApplyStaging -WorkDirectory $workFull -Phase Assert')
if ($assertAt -lt 0) { throw 'Invoke-Smoke must fail-fast Assert-ApplyEvidence before Hyper-V' }
if ($pinAt -lt 0) { throw 'Invoke-Smoke must call Get-WinMintDebloatPinsFromStages before Hyper-V' }
if ($clearAt -lt 0) { throw 'Invoke-Smoke must Clear-WinMintApplyStaging at Assert phase' }
if ($assertAt -ge $pinAt) {
    throw 'Assert-ApplyEvidence fail-fast must appear before Get-WinMintDebloatPinsFromStages in Invoke-Smoke.ps1'
}
if ($pinAt -ge $clearAt) {
    throw 'Get-WinMintDebloatPinsFromStages must appear before Clear-WinMintApplyStaging in Invoke-Smoke.ps1'
}

Write-Output 'Test-DebloatDigestPins ok'
exit 0
