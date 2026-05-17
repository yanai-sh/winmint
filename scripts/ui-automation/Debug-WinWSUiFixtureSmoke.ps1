#Requires -Version 7.3
<#
.SYNOPSIS
    Dev helper: start WinMint-UI -FixtureMode for ~16s, capture stdout/stderr, print tail of debug-55129e.log (NDJSON).
#>
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path -LiteralPath (Join-Path $repo 'WinMint-UI.ps1'))) {
    throw "WinMint-UI.ps1 not found under repo: $repo"
}
$ui = Join-Path $repo 'WinMint-UI.ps1'
$pwsh = (Get-Process -Id $PID).Path
$primary = Join-Path $env:LOCALAPPDATA 'WinWS\logs\debug-55129e.log'
Remove-Item -LiteralPath $primary -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $repo 'debug-55129e.log') -Force -ErrorAction SilentlyContinue
$out = Join-Path $repo 'output\Debug-WinWSUiFixtureSmoke-stdout.txt'
$err = Join-Path $repo 'output\Debug-WinWSUiFixtureSmoke-stderr.txt'
$null = New-Item -ItemType Directory -Path (Split-Path $out -Parent) -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue
$p = Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile', '-STA', '-File', $ui, '-FixtureMode') `
    -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
Start-Sleep -Seconds 16
$killed = $false
if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    $killed = $true
}
$p.Refresh()
if ($killed) {
    Write-Host 'child: stopped after 16s timeout (FixtureMode keeps Dispatcher.Run() open — expected).'
} elseif ($p.HasExited) {
    Write-Host ('child exit code: {0}' -f $p.ExitCode)
} else {
    Write-Host 'child: state unknown after stop attempt.'
}
if (Test-Path -LiteralPath $out) { Write-Host '--- stdout ---'; Get-Content -LiteralPath $out -Tail 25 }
if (Test-Path -LiteralPath $err) { Write-Host '--- stderr ---'; Get-Content -LiteralPath $err -Tail 25 }
if (Test-Path -LiteralPath $primary) {
    Write-Host '--- NDJSON tail ---'
    Get-Content -LiteralPath $primary -Tail 40
} else {
    Write-Host 'No debug log at' $primary 'exit=' $p.ExitCode
}
