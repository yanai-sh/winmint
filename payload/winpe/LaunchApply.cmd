@echo off
setlocal EnableExtensions
echo WinMint: initializing Windows PE...
call wpeinit
set "PATH=%SystemRoot%\System32;%PATH%"
set INSTALL=
for /L %%i in (1,1,10) do (
  if not defined INSTALL (
    for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
      if exist %%d:\sources\install.wim set INSTALL=%%d
    )
    if not defined INSTALL (
      mountvol /e >nul 2>&1
      timeout /t 1 /nobreak >nul 2>&1
    )
  )
)
if not defined INSTALL (
  echo WinMint: install.wim not found on any drive
  exit /b 1
)
echo WinMint: found install.wim on drive %INSTALL%:
set WORK=%TEMP%\winmint
if not exist "%WORK%" mkdir "%WORK%"
set LIST=%WORK%\disks.txt
set OVERRIDE=
if exist "%INSTALL%:\winmint-target-disk.txt" (
  for /f "usebackq delims=" %%o in ("%INSTALL%:\winmint-target-disk.txt") do if not defined OVERRIDE set OVERRIDE=%%o
)
set TARGET=
set EXTRA=
> "%WORK%\listdisk.txt" (
  echo list disk
  echo exit
)
set TRY=0
:winmint_wait_disk
set /a TRY+=1
if %TRY% GTR 20 goto :winmint_wait_done
if defined TARGET goto :winmint_wait_done
echo WinMint: waiting for a fixed disk (try %TRY%)...
diskpart /s "%WORK%\listdisk.txt" > "%LIST%"
echo WinMint: diskpart list:
type "%LIST%"
set EXTRA=
for /f "usebackq tokens=1,2" %%a in ("%LIST%") do if /i "%%a"=="Disk" if not "%%b"=="###" call :winmint_pick %%b
if not defined TARGET (
  timeout /t 1 /nobreak >nul 2>&1
  goto :winmint_wait_disk
)
:winmint_wait_done
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
  echo online disk noerr
  echo attributes disk clear readonly noerr
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
echo WinMint: partitioning disk %TARGET%...
diskpart /s "%DP%"
if errorlevel 1 (
  echo WinMint: diskpart failed
  exit /b 1
)
echo WinMint: applying install.wim Index:1 to W:\...
dism /English /Apply-Image /ImageFile:%INSTALL%:\sources\install.wim /Index:1 /ApplyDir:W:\
if errorlevel 1 (
  echo WinMint: dism Apply-Image failed
  exit /b 1
)
echo WinMint: writing UEFI boot files to S:\...
bcdboot W:\Windows /s S: /f UEFI
if errorlevel 1 (
  echo WinMint: bcdboot failed
  exit /b 1
)
if exist "%INSTALL%:\OobeUnattend.xml" (
  if not exist W:\Windows\Panther mkdir W:\Windows\Panther
  copy /Y "%INSTALL%:\OobeUnattend.xml" W:\Windows\Panther\unattend.xml
)
echo WinMint: configuring LabConfig bypasses in offline SYSTEM hive...
reg load HKLM\WinMintApply W:\Windows\System32\config\SYSTEM
if errorlevel 1 (
  echo WinMint: reg load SYSTEM failed
  exit /b 1
)
reg add HKLM\WinMintApply\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f
reg add HKLM\WinMintApply\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f
reg add HKLM\WinMintApply\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f
reg unload HKLM\WinMintApply
echo WinMint: apply complete. Rebooting into installed Windows...
wpeutil reboot
exit /b 0

rem Keeps a fixed disk as a candidate. USB is excluded categorically, so the installer can never
rem erase the media it booted from, and disk numbers stay discovered rather than configured.
rem ponytail: parses English diskpart output - a localised WinPE finds no candidates and refuses,
rem which is the safe direction. Match on localised headings if that ever needs to work.
:winmint_pick
set N=%1
> "%WORK%\d%N%in.txt" (
  echo select disk %N%
  echo detail disk
  echo exit
)
diskpart /s "%WORK%\d%N%in.txt" > "%WORK%\d%N%.txt"
set ISUSB=
for /f "usebackq tokens=1,2,3" %%a in ("%WORK%\d%N%.txt") do if /i "%%a"=="Type" if /i "%%c"=="USB" set ISUSB=1
if defined ISUSB goto :eof
if defined OVERRIDE (
  %SystemRoot%\System32\findstr.exe /i /c:"%OVERRIDE%" "%WORK%\d%N%.txt" >nul
  if errorlevel 1 goto :eof
)
if defined TARGET (set EXTRA=1) else (set TARGET=%N%)
goto :eof
