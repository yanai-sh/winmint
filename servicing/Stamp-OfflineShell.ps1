#requires -Version 7.6
param(
    [Parameter(Mandatory)] [string] $ShellTarget,
    [Parameter(Mandatory)] [string] $MountDir
)
# Offline Winlogon Shell → Supervisor path (must match Machine setup verify target).
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

Write-Output "StampOfflineShell ok"
exit 0
