#Requires -Version 7.6
# Static contract: guest wait snapshot must not use expensive Win32_Process scans.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$snapshotPath = Join-Path $repoRoot 'tools\vm\Get-WinMintVmGuestWaitSnapshot.ps1'
$text = Get-Content -LiteralPath $snapshotPath -Raw

if ($text -notmatch 'function\s+Get-WinMintVmGuestWaitSnapshot') {
    throw 'Get-WinMintVmGuestWaitSnapshot not found in tools/vm/Get-WinMintVmGuestWaitSnapshot.ps1'
}

$start = $text.IndexOf('function Get-WinMintVmGuestWaitSnapshot')
$nextFunc = $text.IndexOf("`nfunction ", $start + 1)
if ($nextFunc -lt 0) { $nextFunc = $text.Length }
$body = $text.Substring($start, $nextFunc - $start)

if ($body -match 'Win32_Process') {
    if ($body -notmatch 'Win32_Process[^\r\n]*-Filter') {
        throw 'Get-WinMintVmGuestWaitSnapshot must not enumerate Win32_Process without -Filter.'
    }
}

if ($body -notmatch "Get-Process\s+-Name\s+'WinMintSetupShell'") {
    throw 'Get-WinMintVmGuestWaitSnapshot must use Get-Process -Name WinMintSetupShell.'
}

if ($body -notmatch 'runtime-state\.json') {
    throw 'Get-WinMintVmGuestWaitSnapshot must read runtime-state.json for progress polling.'
}

if ($body -notmatch 'setup-shell-status\.json') {
    throw 'Get-WinMintVmGuestWaitSnapshot must fall back to setup-shell-status.json when runtime-state is absent.'
}

if ($body -notmatch 'setupShellProgressPct') {
    throw 'Get-WinMintVmGuestWaitSnapshot must expose setupShellProgressPct.'
}

$consoleText = Get-Content -LiteralPath (Join-Path $repoRoot 'tools\vm\WinMint-VmConsole.ps1') -Raw
if ($consoleText -notmatch 'Get-WinMintVmGuestWaitSnapshot\.ps1') {
    throw 'WinMint-VmConsole.ps1 must dot-source tools/vm/Get-WinMintVmGuestWaitSnapshot.ps1.'
}
if ($consoleText -notmatch "Join-Path \`$libRoot 'VmGuest\.ps1'|lib[/\\]VmGuest\.ps1") {
    throw 'WinMint-VmConsole.ps1 must dot-source tools/vm/lib/VmGuest.ps1.'
}

$acceptanceText = Get-Content -LiteralPath (Join-Path $repoRoot 'tools\vm\Invoke-WinMintVmAcceptance.ps1') -Raw
if ($acceptanceText -notmatch 'Get-WinMintVmGuestWaitSnapshot\.ps1') {
    throw 'Invoke-WinMintVmAcceptance.ps1 must poll guest via Get-WinMintVmGuestWaitSnapshot.ps1 -FilePath.'
}

Write-Host 'VM guest wait snapshot contract: OK'
exit 0
