#requires -Version 7.6
param(
    [Parameter(Mandatory)] [string] $MountDir
)
# Offline OneDrive erase: delete Setup stubs + clear Run/RunOnce hooks so Setup never ships in the ISO.
# Known Folder paths stay under %USERPROFILE% via StampOfflineDefaultUser (ProductPosture), not here.

function Remove-TrustedInstallerFile {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Output "onedrive erase skip missing: $Path"
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Path, 'Remove TrustedInstaller-owned file')) {
        return
    }
    & takeown.exe /F $Path /A | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "takeown failed: $Path exit $LASTEXITCODE" }
    # Administrators (BA) — S-1-5-32-544
    & icacls.exe $Path /grant '*S-1-5-32-544:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls grant failed: $Path exit $LASTEXITCODE" }
    Remove-Item -LiteralPath $Path -Force
    Write-Output "onedrive erase deleted: $Path"
}

function Clear-WinMintOfflineOneDriveRun {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $HiveKey,
        [Parameter(Mandatory)] [string] $SubKey
    )
    # ponytail: reg.exe only — .NET OpenSubKey on loaded offline hives sticks handles and poisons later loads.
    $keyPath = "$HiveKey\$SubKey"
    $query = & reg.exe query $keyPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Output "onedrive erase Run skip missing: $keyPath"
        return
    }
    foreach ($line in @($query)) {
        if ($line -notmatch '^\s+(\S+)\s+REG_\w+\s+') { continue }
        $name = $Matches[1]
        if ($name -notmatch '(?i)OneDrive') { continue }
        $target = "$keyPath\$name"
        if (-not $PSCmdlet.ShouldProcess($target, 'Clear OneDrive Run value')) {
            continue
        }
        & reg.exe delete $keyPath /v $name /f | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "reg delete failed: $target exit $LASTEXITCODE" }
        Write-Output "onedrive erase Run cleared: $target"
    }
}

function Invoke-OfflineHiveLoad {
    param(
        [Parameter(Mandatory)] [string] $HiveKey,
        [Parameter(Mandatory)] [string] $HivePath
    )
    if (-not (Test-Path -LiteralPath $HivePath -PathType Leaf)) { throw "hive missing: $HivePath" }
    Write-Output "REG LOAD $HiveKey"
    & reg.exe load $HiveKey $HivePath
    if ($LASTEXITCODE -ne 0) { throw "reg load failed: $HiveKey exit $LASTEXITCODE" }
}

function Invoke-OfflineHiveUnload {
    param([Parameter(Mandatory)] [string] $HiveKey)
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    Start-Sleep -Milliseconds 500
    & reg.exe unload $HiveKey
    if ($LASTEXITCODE -ne 0) { throw "reg unload failed: $HiveKey exit $LASTEXITCODE" }
}

foreach ($rel in @(
        'Windows\System32\OneDriveSetup.exe',
        'Windows\SysWOW64\OneDriveSetup.exe'
    )) {
    Remove-TrustedInstallerFile -Path (Join-Path $mountDir $rel)
}

foreach ($rel in @(
        'Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk',
        'Users\Default\Desktop\OneDrive.lnk'
    )) {
    $lnk = Join-Path $mountDir $rel
    if (Test-Path -LiteralPath $lnk -PathType Leaf) {
        Remove-Item -LiteralPath $lnk -Force
        Write-Output "onedrive erase deleted: $lnk"
    }
}

$softKey = 'HKLM\WinMintOdSoft'
Invoke-OfflineHiveLoad -HiveKey $softKey -HivePath (Join-Path $mountDir 'Windows\System32\config\SOFTWARE')
try {
    foreach ($sub in @(
            'Microsoft\Windows\CurrentVersion\Run',
            'Microsoft\Windows\CurrentVersion\RunOnce',
            'WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
            'WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'
        )) {
        Clear-WinMintOfflineOneDriveRun -HiveKey $softKey -SubKey $sub
    }
}
finally {
    Invoke-OfflineHiveUnload -HiveKey $softKey
}

$duKey = 'HKLM\WinMintOdDU'
Invoke-OfflineHiveLoad -HiveKey $duKey -HivePath (Join-Path $mountDir 'Users\Default\NTUSER.DAT')
try {
    foreach ($sub in @(
            'SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
        )) {
        Clear-WinMintOfflineOneDriveRun -HiveKey $duKey -SubKey $sub
    }
}
finally {
    Invoke-OfflineHiveUnload -HiveKey $duKey
}

Write-Output 'EraseOfflineOneDrive ok'
exit 0
