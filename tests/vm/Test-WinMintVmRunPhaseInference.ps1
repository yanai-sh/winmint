#Requires -Version 7.6
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tools\vm\WinMint-VmConsole.ps1')

$cases = @(
    @{ Tail = @('=== Build ===', 'Building ISO from profile'); Expected = 'BuildBoot-build' }
    @{ Tail = @('waiting for first-logon breadcrumb'); Expected = 'BuildBoot-breadcrumb' }
    @{ Tail = @('=== Build ===', 'waiting for first-logon breadcrumb'); StoredPhase = 'Build'; Expected = 'BuildBoot-breadcrumb' }
    @{ Tail = @('=== Wait for FirstLogon ==='); Expected = 'Wait for FirstLogon' }
)

foreach ($case in $cases) {
    $stored = if ($case.StoredPhase) { $case.StoredPhase } else { 'starting' }
    $phase = Get-WinMintVmInferredRunPhase -Tail $case.Tail -StoredPhase $stored
    if ($phase -ne $case.Expected) {
        throw "Expected phase '$($case.Expected)' got '$phase'"
    }
}

Write-Host 'VM run phase inference contract: OK'
exit 0
