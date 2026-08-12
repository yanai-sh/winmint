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
dism /English /Apply-Image /ImageFile:%INSTALL%:\sources\install.wim /Index:1 /ApplyDir:W:\
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
