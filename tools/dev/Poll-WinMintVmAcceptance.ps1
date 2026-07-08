#Requires -Version 7.6
param(
    [int]$IntervalSeconds = 120,
    [int]$MaxPolls = 60
)
$statusScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'vm\Get-WinMintVmAcceptanceStatus.ps1'
for ($i = 1; $i -le $MaxPolls; $i++) {
    $s = & $statusScript | ConvertFrom-Json
    $tail = @($s.tail | Select-Object -Last 1) -join ' | '
    Write-Host ("[{0}] poll {1}/{2} status={3} complete={4} phase={5} elapsed={6}m err={7}" -f `
        (Get-Date -Format 'HH:mm:ss'), $i, $MaxPolls, $s.status, $s.complete, $s.currentPhase, $s.elapsedMinutes, $s.error)
    if ($tail) { Write-Host "  tail: $tail" }
    if ($s.complete) {
        if ($s.status -eq 'passed' -and $s.verdict -eq 'pass') { exit 0 }
        exit 1
    }
    Start-Sleep -Seconds $IntervalSeconds
}
exit 2
