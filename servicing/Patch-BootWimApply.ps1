#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
$mediaDir = $Parameters['mediaDir']
$mountDir = $Parameters['mountDir']
# Source-ISO edition index is unrelated: after single-image export, apply target is always index 1.
if ([string]::IsNullOrWhiteSpace($mediaDir)) { throw 'mediaDir required' }
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }
$applyWimIndex = 1
$expectedMarker = "apply+wimIndex=$applyWimIndex"
$indexToken = "/Index:$applyWimIndex"

# Spike #70: 3-partition GPT (EFI 100 MB, MSR 16 MB, primary) — WinPE apply disk layout.
# LabConfig on applied-image SYSTEM hive (not boot.wim) — Hyper-V no-vTPM VMs read it at first boot.
$bootWim = Join-Path $mediaDir 'sources\boot.wim'
$bootMarker = Join-Path $mediaDir 'sources\.winmint-boot-apply'
$legacyMarker = Join-Path $mediaDir 'sources\.winmint-boot-legacy'
if (-not (Test-Path -LiteralPath $bootWim)) {
    throw "boot.wim missing under media (expected $bootWim)"
}

function Test-LaunchApplyPatched {
    param([string] $Wim, [string] $Mount, [int] $Index, [string] $Token)
    & dism.exe /English /Mount-Image /ImageFile:$Wim /Index:$Index /MountDir:$Mount /ReadOnly
    if ($LASTEXITCODE -ne 0) { return $false }
    try {
        $launch = Join-Path $Mount 'Windows\System32\LaunchApply.cmd'
        $winpeshl = Join-Path $Mount 'Windows\System32\winpeshl.ini'
        if (-not (Test-Path -LiteralPath $launch)) { return $false }
        if (-not (Test-Path -LiteralPath $winpeshl)) { return $false }
        $body = Get-Content -LiteralPath $launch -Raw -Encoding ascii
        if ($body -notlike "*$Token*") { return $false }
        if ($body -match '/Index:(\d+)' -and [int]$Matches[1] -ne $applyWimIndex) { return $false }
        # Media patched before the target-disk guard existed must be re-patched, not skipped.
        if ($body -notmatch 'winmint_pick') { return $false }
        $ini = Get-Content -LiteralPath $winpeshl -Raw -Encoding ascii
        return ($ini -match 'LaunchApply\.cmd')
    }
    finally {
        & dism.exe /English /Unmount-Image /MountDir:$Mount /Discard | Out-Null
    }
}

$bootMount = Join-Path (Split-Path -Parent $mountDir) 'boot-mount'
if (Test-Path -LiteralPath $bootMount) {
    & dism.exe /English /Unmount-Image /MountDir:$bootMount /Discard 2>$null | Out-Null
    Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $bootMount | Out-Null

# ponytail: skip only when marker + index-1 LaunchApply both prove apply+wimIndex=1 (stale marker hid Index:3).
if (Test-Path -LiteralPath $bootMarker) {
    $markerText = (Get-Content -LiteralPath $bootMarker -Raw -Encoding utf8).Trim()
    if ($markerText -eq $expectedMarker -and (Test-LaunchApplyPatched -Wim $bootWim -Mount $bootMount -Index 1 -Token $indexToken)) {
        Remove-Item -LiteralPath $legacyMarker -Force -ErrorAction SilentlyContinue
        Write-Output 'PatchBootWimApply skipped (already patched; LaunchApply Index:1 verified)'
        Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
        exit 0
    }
    Write-Output "PatchBootWimApply re-patch (marker='$markerText' or LaunchApply mismatch)"
    Remove-Item -LiteralPath $bootMarker -Force -ErrorAction SilentlyContinue
}

$launchApply = @"
@echo off
setlocal EnableExtensions
call wpeinit
set INSTALL=
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
  if exist %%d:\sources\install.wim set INSTALL=%%d
)
if not defined INSTALL (
  echo WinMint: install.wim not found on any drive
  exit /b 1
)
set WORK=%TEMP%\winmint
if not exist "%WORK%" mkdir "%WORK%"
set LIST=%WORK%\disks.txt
echo list disk | diskpart > "%LIST%"
if errorlevel 1 (
  echo WinMint: diskpart could not enumerate disks
  exit /b 1
)
set OVERRIDE=
if exist "%INSTALL%:\winmint-target-disk.txt" (
  for /f "usebackq delims=" %%o in ("%INSTALL%:\winmint-target-disk.txt") do if not defined OVERRIDE set OVERRIDE=%%o
)
set TARGET=
set EXTRA=
for /f "tokens=2" %%n in ('findstr /r /c:"^  Disk [0-9]" "%LIST%"') do call :winmint_pick %%n
if not defined TARGET (
  echo WinMint: no fixed disk to erase - every disk reports USB, or none matched the override.
  type "%LIST%"
  exit /b 1
)
if defined EXTRA (
  echo WinMint: more than one fixed disk - refusing to guess which one to erase.
  type "%LIST%"
  echo Put a unique model substring in %INSTALL%:\winmint-target-disk.txt and reboot.
  exit /b 1
)
echo WinMint: erasing disk %TARGET%
set DP=%WORK%\diskpart.txt
> "%DP%" (
  echo select disk %TARGET%
  echo clean
  echo convert gpt
  echo create partition efi size=100
  echo format quick fs=fat32 label=System
  echo assign letter=S
  echo create partition msr size=16
  echo create partition primary
  echo format quick fs=ntfs label=Windows
  echo assign letter=W
  echo exit
)
diskpart /s "%DP%"
if errorlevel 1 exit /b 1
dism /English /Apply-Image /ImageFile:%INSTALL%:\sources\install.wim /Index:$applyWimIndex /ApplyDir:W:\
if errorlevel 1 exit /b 1
bcdboot W:\Windows /s S: /f UEFI
if errorlevel 1 exit /b 1
if exist "%INSTALL%:\OobeUnattend.xml" (
  if not exist W:\Windows\Panther mkdir W:\Windows\Panther
  copy /Y "%INSTALL%:\OobeUnattend.xml" W:\Windows\Panther\unattend.xml
)
reg load HKLM\WinMintApply W:\Windows\System32\config\SYSTEM
if errorlevel 1 exit /b 1
reg add HKLM\WinMintApply\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f
reg add HKLM\WinMintApply\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f
reg add HKLM\WinMintApply\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f
reg unload HKLM\WinMintApply
wpeutil reboot
exit /b 0

rem Keeps a fixed disk as a candidate. USB is excluded categorically, so the installer can never
rem erase the media it booted from, and disk numbers stay discovered rather than configured.
rem ponytail: parses English diskpart output - a localised WinPE finds no candidates and refuses,
rem which is the safe direction. Match on localised headings if that ever needs to work.
:winmint_pick
set N=%1
(echo select disk %N%&echo detail disk) | diskpart > "%WORK%\d%N%.txt"
findstr /i /r /c:"^Type.*USB" "%WORK%\d%N%.txt" >nul
if not errorlevel 1 goto :eof
if defined OVERRIDE (
  findstr /i /c:"%OVERRIDE%" "%WORK%\d%N%.txt" >nul
  if errorlevel 1 goto :eof
)
if defined TARGET (set EXTRA=1) else (set TARGET=%N%)
goto :eof
"@

$bootItem = Get-Item -LiteralPath $bootWim
if ($bootItem.IsReadOnly) { $bootItem.IsReadOnly = $false }
$info = & dism.exe /English /Get-WimInfo /WimFile:$bootWim 2>&1 | Out-String
$indexes = @([regex]::Matches($info, '(?m)^Index : (\d+)\s*$') | ForEach-Object { [int]$_.Groups[1].Value })
if ($indexes.Count -eq 0) { throw 'boot.wim has no indexes' }

$winpeshl = @"
[LaunchApps]
%SYSTEMDRIVE%\Windows\System32\LaunchApply.cmd
"@

foreach ($index in $indexes) {
    Write-Output "Patch boot.wim index $index (WinPE apply launcher)"
    & dism.exe /English /Mount-Image /ImageFile:$bootWim /Index:$index /MountDir:$bootMount
    if ($LASTEXITCODE -ne 0) { throw "Mount boot.wim:$index failed: $LASTEXITCODE" }
    try {
        Set-Content -LiteralPath (Join-Path $bootMount 'Windows\System32\LaunchApply.cmd') -Value $launchApply -Encoding ascii
        Set-Content -LiteralPath (Join-Path $bootMount 'Windows\System32\winpeshl.ini') -Value $winpeshl -Encoding ascii
    }
    finally {
        & dism.exe /English /Unmount-Image /MountDir:$bootMount /Commit
        if ($LASTEXITCODE -ne 0) { throw "Unmount boot.wim:$index failed: $LASTEXITCODE" }
    }
}

Set-Content -LiteralPath $bootMarker -Value $expectedMarker -Encoding utf8
# Apply lane supersedes legacy LabConfig-in-boot.wim marker; leave no ambiguous dual story.
Remove-Item -LiteralPath $legacyMarker -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
Write-Output 'PatchBootWimApply ok'
exit 0
