#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
$mediaDir = $Parameters['mediaDir']
$mountDir = $Parameters['mountDir']
$wimIndex = [int]$Parameters['wimIndex']
if ([string]::IsNullOrWhiteSpace($mediaDir)) { throw 'mediaDir required' }
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }
if ($wimIndex -lt 1) { throw "wimIndex must be >= 1 (got $wimIndex)" }

# Spike #70: 3-partition GPT (EFI 100 MB, MSR 16 MB, primary) — ports BuildAutounattendXml disk intent.
# LabConfig on applied-image SYSTEM hive (not boot.wim) — Hyper-V no-vTPM VMs read it at first boot.
# ponytail: boot.wim mount loop mirrors Inject-Unattend.ps1; extract shared helper if a third lane appears.
$bootMarker = Join-Path $mediaDir 'sources\.winmint-boot-apply'
if (-not (Test-Path -LiteralPath $bootWim)) {
    throw "boot.wim missing under media (expected $bootWim)"
}
if (Test-Path -LiteralPath $bootMarker) {
    Write-Output 'PatchBootWimApply skipped (already patched)'
    exit 0
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
set DP=%TEMP%\winmint-diskpart.txt
> "%DP%" (
  echo select disk 0
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
dism /English /Apply-Image /ImageFile:%INSTALL%:\sources\install.wim /Index:$wimIndex /ApplyDir:W:\
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
"@

$bootItem = Get-Item -LiteralPath $bootWim
if ($bootItem.IsReadOnly) { $bootItem.IsReadOnly = $false }
$bootMount = Join-Path (Split-Path -Parent $mountDir) 'boot-mount'
if (Test-Path -LiteralPath $bootMount) {
    & dism.exe /English /Unmount-Image /MountDir:$bootMount /Discard 2>$null | Out-Null
    Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $bootMount | Out-Null
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

Set-Content -LiteralPath $bootMarker -Value "apply+wimIndex=$wimIndex" -Encoding utf8
Remove-Item -LiteralPath $bootMount -Recurse -Force -ErrorAction SilentlyContinue
Write-Output 'PatchBootWimApply ok'
exit 0
