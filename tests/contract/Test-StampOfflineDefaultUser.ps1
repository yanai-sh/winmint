#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$kernel = Get-Content -LiteralPath (Join-Path $repo 'servicing\Stamp-OfflineDefaultUser.ps1') -Raw
if ($kernel -notmatch 'NTUSER\.DAT') { throw 'Stamp-OfflineDefaultUser must load Users\Default\NTUSER.DAT' }
if ($kernel -notmatch 'ConvertFrom-Json') { throw 'Stamp-OfflineDefaultUser must read default-user.json' }
if ($kernel -notmatch 'finally') { throw 'Stamp-OfflineDefaultUser must unload the hive in finally' }
if ($kernel -notmatch 'reg\.exe add') { throw 'Stamp-OfflineDefaultUser must fall back to reg.exe on denied .NET writes' }
if ($kernel -notmatch 'must not create Policies') { throw 'Stamp-OfflineDefaultUser must reject Policies rows' }
if ($kernel -match 'Clear-WinMintOfflineOneDriveRun') { throw 'Stamp-OfflineDefaultUser must not clear OneDrive Run values' }

$work = Join-Path $env:TEMP ("winmint-du-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
    $probe = Join-Path $work 'probe.ps1'
    @'
param([Parameter(Mandatory)][string]$DefaultUserPath)
$rows = @(Get-Content -LiteralPath $DefaultUserPath -Raw | ConvertFrom-Json)
if ($rows.Count -eq 0) { throw 'default-user.json empty' }
foreach ($row in $rows) {
    $sub = [string]$row.SubKey
    if ($sub -match '(?i)(^|\\)Policies(\\+|$)') {
        throw "default-user row must not create Policies: $sub"
    }
}
'@ | Set-Content -LiteralPath $probe -Encoding utf8

    $bad = Join-Path $work 'bad.json'
    '[{"hive":"NTUSER","subKey":"SOFTWARE\\Policies\\Microsoft\\Windows\\Explorer","name":"Bad","regType":"REG_DWORD","data":"1","family":"quiet"}]' |
        Set-Content -LiteralPath $bad -Encoding utf8
    $err = $null
    try {
        & $probe -DefaultUserPath $bad
    }
    catch {
        $err = [string]$_
    }
    if ($err -notmatch 'must not create Policies') {
        throw "Policies guard did not fire: $err"
    }

    $ok = Join-Path $work 'ok.json'
    '[{"hive":"NTUSER","subKey":"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize","name":"AppsUseLightTheme","regType":"REG_DWORD","data":"0","family":"quiet"}]' |
        Set-Content -LiteralPath $ok -Encoding utf8
    & $probe -DefaultUserPath $ok
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Test-StampOfflineDefaultUser ok'
exit 0
