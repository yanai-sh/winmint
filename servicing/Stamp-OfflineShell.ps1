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
if (-not (Test-Path -LiteralPath $hiveSoftware)) { throw "SOFTWARE hive missing: $hiveSoftware" }

$hiveKey = 'HKLM\WinMintSoft'
$winlogon = 'HKLM\WinMintSoft\Microsoft\Windows NT\CurrentVersion\Winlogon'

Write-Output "REG LOAD $hiveKey"
& reg.exe load $hiveKey $hiveSoftware
if ($LASTEXITCODE -ne 0) { throw "reg load failed: $LASTEXITCODE" }
try {
    & reg.exe add $winlogon /v Shell /t REG_SZ /d $shellTarget /f
    if ($LASTEXITCODE -ne 0) { throw "reg add Shell failed: $LASTEXITCODE" }
    Write-Output "Shell=$shellTarget"
}
finally {
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    Start-Sleep -Milliseconds 500
    & reg.exe unload $hiveKey
    if ($LASTEXITCODE -ne 0) { throw "reg unload failed: $LASTEXITCODE" }
}

$stampNote = Join-Path $mountDir 'Windows\WinMint\shell-stamp.txt'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stampNote) | Out-Null
Set-Content -LiteralPath $stampNote -Value "Shell=$shellTarget" -Encoding utf8
Write-Output "StampOfflineShell ok"
exit 0
