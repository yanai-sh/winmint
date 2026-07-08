#Requires -Version 7.6
# Contract: guest PSDirect helper runs host scripts under bundled guest pwsh 7.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'tools\vm\WinMint-VmConsole.ps1')

$guestText = Get-Content -LiteralPath (Join-Path $repoRoot 'tools\vm\lib\VmGuest.ps1') -Raw
$failures = [System.Collections.Generic.List[string]]::new()

foreach ($expected in @(
        'function Test-WinMintVmGuestPsDirectRetryable'
        'WinMint guest harness requires bundled PowerShell 7'
        'winmint-harness-'
    )) {
    if ($guestText -notmatch [regex]::Escape($expected)) {
        $failures.Add("tools/vm/lib/VmGuest.ps1 missing '$expected'.")
    }
}

$evidenceText = Get-Content -LiteralPath (Join-Path $repoRoot 'tools\vm\lib\VmEvidence.ps1') -Raw
if ($evidenceText -notmatch 'nativeLogOk = \$true') {
    $failures.Add("tools/vm/lib/VmEvidence.ps1 missing 'nativeLogOk = `$true'.")
}

if (-not (Test-WinMintVmGuestPsDirectRetryable -Message 'A remote session might have ended')) {
    $failures.Add('Transient PSDirect errors should be retryable.')
}
if (Test-WinMintVmGuestPsDirectRetryable -Message 'The operation has timed out') {
    $failures.Add('Timeouts must not be treated as transient PSDirect retries.')
}

$acceptanceText = Get-Content -LiteralPath (Join-Path $repoRoot 'tools\vm\Invoke-WinMintVmAcceptance.ps1') -Raw
if ($acceptanceText -notmatch 'Panther') {
    $failures.Add('Invoke-WinMintVmAcceptance.ps1 should pull Panther setup diagnostics into evidence.')
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'VM guest command contract: OK'
exit 0
