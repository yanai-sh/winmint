#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
# Offline Winlogon Shell → Supervisor path (must match Machine setup verify target).
$shellTarget = $Parameters['shellTarget']
$mountDir = $Parameters['mountDir']
if ([string]::IsNullOrWhiteSpace($shellTarget)) { throw 'shellTarget required' }
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }

$hiveSoftware = Join-Path $mountDir 'Windows\System32\config\SOFTWARE'
$stampNote = Join-Path $mountDir 'Windows\WinMint\shell-stamp.txt'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stampNote) | Out-Null
# ponytail: real offline hive load/REG LOAD lands with ISO acceptance; record intended Shell path for evidence.
Set-Content -LiteralPath $stampNote -Value "Shell=$shellTarget`nHive=$hiveSoftware" -Encoding utf8
Write-Host "StampOfflineShell ok shellTarget=$shellTarget"
exit 0
