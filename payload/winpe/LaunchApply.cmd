@echo off
setlocal EnableExtensions
rem Hyper-V VMConnect click enters cmd Select Mode (Quick Edit) and pauses DISM until another click/Enter.
reg add HKCU\Console /v QuickEdit /t REG_DWORD /d 0 /f >nul
rem ponytail: respawn so the apply console is created after QuickEdit=0; SetConsoleMode / #119 if the extra window matters
if not defined WINMINT_QE (
  set WINMINT_QE=1
  start "WinMint" /wait /d "%~dp0" "%ComSpec%" /c "%~f0" %*
  exit /b %ERRORLEVEL%
)
echo WinMint: initializing Windows PE...
call wpeinit
set "PATH=%SystemRoot%\System32;%PATH%"
rem Microsoft: wpeutil UpdateBootInfo records the volume WinPE booted from.
rem PEBootRamdiskSourceDrive is that letter. detail volume turns it into a disk
rem number. That number is the stick, including when diskpart's Type line is
rem SCSI, SATA, NVMe, or RAID. A Type USB line is only an extra skip for a
rem second stick that diskpart does label USB.
wpeutil UpdateBootInfo
set INSTALL=
set BOOTDISK=
set PAYLOADDISK=
set WINMINT_BOOT_TAG=
for /L %%i in (1,1,10) do if not defined INSTALL call :winmint_find_install
if not defined INSTALL (
  if defined WINMINT_BOOT_TAG (
    echo WinMint: install.wim not found on any drive
  ) else (
    echo WinMint: install.wim not found on the boot disk
  )
  exit /b 1
)
if defined BOOTDISK (
  echo WinMint: boot disk %BOOTDISK%, install.wim on %INSTALL%:
) else (
  echo WinMint: boot letter was not recorded. Payload disk %PAYLOADDISK% on %INSTALL%: is excluded.
)
rem Test-only media asks WinPE to prove that firmware booted the removable path and
rem that its NTFS payload was visible. This exits before enumerating target disks.
if exist "%INSTALL%:\winmint-boot-probe.txt" goto :winmint_boot_probe
rem A second boot of this USB must not clean the disk. A finished install turns the PC off.
if exist "%INSTALL%:\winmint-reinstall.txt" (
  del /f /q "%INSTALL%:\winmint-reinstall.txt"
  set REINSTALL=1
  echo WinMint: reinstall requested. The internal disk will be erased.
)
if not defined REINSTALL if exist "%INSTALL%:\winmint-applied.txt" goto :winmint_finished
set WORK=%TEMP%\winmint
if not exist "%WORK%" mkdir "%WORK%"
set LIST=%WORK%\disks.txt
set OVERRIDE=
if exist "%INSTALL%:\winmint-target-disk.txt" (
  for /f "usebackq delims=" %%o in ("%INSTALL%:\winmint-target-disk.txt") do if not defined OVERRIDE set OVERRIDE=%%o
)
set TARGET=
set EXTRA=
call :winmint_bus_types
if defined WINMINT_BUS_FAIL (
  echo WinMint: could not read disk bus types
  exit /b 1
)
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
  echo WinMint: no fixed disk to erase. The boot disk is excluded. Every other disk reports USB, or none matched the override.
  type "%LIST%"
  exit /b 1
)
if defined EXTRA (
  echo WinMint: more than one fixed disk - refusing to guess which one to erase.
  type "%LIST%"
  echo Put a unique model substring in %INSTALL%:\winmint-target-disk.txt and reboot.
  exit /b 1
)
if not defined REINSTALL call :winmint_see_applied
if defined HANDED goto :winmint_finished
if defined PROBEFAIL (
  echo WinMint: could not check the internal disk for an existing install. Refusing to erase.
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
  echo create partition efi size=300
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
rem The applied image's bcdboot knows /offline /bootex. WinPE's copy may not.
rem /s still targets the internal EFI partition. /offline /bootex selects the
rem Windows UEFI CA 2023 boot manager. Surface rejects the 2011 manager.
set BCDBOOT=W:\Windows\System32\bcdboot.exe
if not exist "%BCDBOOT%" set BCDBOOT=bcdboot
"%BCDBOOT%" W:\Windows /s S: /f UEFI /offline /bootex
if errorlevel 1 (
  echo WinMint: bcdboot /offline /bootex failed. The 2011 UEFI CA boot manager is not a fallback.
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
echo WinMint apply complete> "%INSTALL%:\winmint-applied.txt"
echo WinMint apply complete> "W:\Windows\WinMint.applied"
rem The markers are already written. A missing wim, a failed shrink, or a failed
rem reagentc reboots. The next boot sees winmint-applied.txt and shuts down.
echo WinMint: registering Windows RE...
if not exist W:\Windows\System32\Recovery\Winre.wim (
  echo WinMint: Winre.wim missing from the applied image
  wpeutil reboot
  exit /b 1
)
set WINRE_BYTES=
for %%f in ("W:\Windows\System32\Recovery\Winre.wim") do set WINRE_BYTES=%%~zf
set WINRE_MB=
set SHRINK_MB=
set /a WINRE_MB=(WINRE_BYTES+1048575)/1048576
set /a SHRINK_MB=WINRE_MB+250
if not defined SHRINK_MB (
  echo WinMint: Winre.wim size could not be read
  wpeutil reboot
  exit /b 1
)
rem Shrink Windows by the wim size plus 250 MB, then create the recovery partition
rem in that free space. The inbox Winre.wim stays where the image put it.
> "%WORK%\winre.txt" (
  echo select disk %TARGET%
  echo select volume W
  echo shrink desired=%SHRINK_MB%
  echo create partition primary
  echo format quick fs=ntfs label=Recovery
  echo assign letter=R
  echo set id=de94bba4-06d1-4d40-a16a-bfd50179d6ac
  echo gpt attributes=0x8000000000000001
  echo exit
)
diskpart /s "%WORK%\winre.txt"
if errorlevel 1 (
  echo WinMint: recovery partition failed
  wpeutil reboot
  exit /b 1
)
if not exist R:\ (
  echo WinMint: recovery partition failed
  wpeutil reboot
  exit /b 1
)
if not exist R:\Recovery\WindowsRE mkdir R:\Recovery\WindowsRE
xcopy /h /y "W:\Windows\System32\Recovery\Winre.wim" "R:\Recovery\WindowsRE\"
if errorlevel 1 (
  echo WinMint: could not copy Winre.wim to the recovery partition
  wpeutil reboot
  exit /b 1
)
set REAGENTC=W:\Windows\System32\reagentc.exe
set BCDEDIT=W:\Windows\System32\bcdedit.exe
if not exist "%REAGENTC%" (
  echo WinMint: reagentc.exe missing from the applied image
  wpeutil reboot
  exit /b 1
)
if not exist "%BCDEDIT%" (
  echo WinMint: bcdedit.exe missing from the applied image
  wpeutil reboot
  exit /b 1
)
set OSGUID=
for /f "tokens=1,2" %%a in ('"%BCDEDIT%" /store S:\EFI\Microsoft\Boot\BCD /enum {default} /v') do if /i "%%a"=="identifier" if not defined OSGUID set OSGUID=%%b
set WINRE_GUID_OK=
if defined OSGUID if "%OSGUID:~0,1%"=="{" if "%OSGUID:~9,1%"=="-" set WINRE_GUID_OK=1
if not defined WINRE_GUID_OK (
  echo WinMint: bcdedit did not return the Windows boot identifier
  wpeutil reboot
  exit /b 1
)
"%REAGENTC%" /setreimage /path R:\Recovery\WindowsRE /target W:\Windows
if errorlevel 1 (
  echo WinMint: reagentc /setreimage failed
  wpeutil reboot
  exit /b 1
)
"%REAGENTC%" /enable /osguid %OSGUID%
if errorlevel 1 (
  echo WinMint: reagentc /enable failed
  wpeutil reboot
  exit /b 1
)
echo WinMint: apply complete. Rebooting into installed Windows...
wpeutil reboot
exit /b 0

:winmint_boot_probe
set WINMINT_PROBE_CHALLENGE=
for %%f in ("%INSTALL%:\winmint-boot-probe.txt") do if not "%%~zf"=="32" goto :winmint_boot_probe_invalid
findstr /r /x "[0-9a-f][0-9a-f]*" "%INSTALL%:\winmint-boot-probe.txt" >nul
if errorlevel 1 goto :winmint_boot_probe_invalid
set /p WINMINT_PROBE_CHALLENGE=<"%INSTALL%:\winmint-boot-probe.txt"
if not defined WINMINT_PROBE_CHALLENGE goto :winmint_boot_probe_invalid
set WINMINT_SECURE_BOOT=
for /f "tokens=3" %%s in ('reg query HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State /v UEFISecureBootEnabled 2^>nul ^| findstr /i UEFISecureBootEnabled') do set WINMINT_SECURE_BOOT=%%s
if /i not "%WINMINT_SECURE_BOOT%"=="0x1" goto :winmint_boot_probe_insecure
> "%INSTALL%:\winmint-boot-probe.json" echo {"schemaVersion":"winmint.usb-boot-probe/v1","result":"passed","secureBoot":true,"challenge":"%WINMINT_PROBE_CHALLENGE%"}
echo.
echo WINMINT USB BOOT PROBE PASSED %WINMINT_PROBE_CHALLENGE%
echo Secure Boot loaded WinPE and WinPE found the NTFS payload. No target disk was inspected or changed.
timeout /t 30 /nobreak >nul
wpeutil shutdown
exit /b 0

:winmint_boot_probe_insecure
> "%INSTALL%:\winmint-boot-probe.json" echo {"schemaVersion":"winmint.usb-boot-probe/v1","result":"failed","secureBoot":false,"challenge":"%WINMINT_PROBE_CHALLENGE%"}
echo.
echo WINMINT USB BOOT PROBE FAILED: SECURE BOOT IS NOT ENABLED
timeout /t 30 /nobreak >nul
wpeutil shutdown
exit /b 1

:winmint_boot_probe_invalid
echo WINMINT USB BOOT PROBE FAILED: CHALLENGE IS MISSING
timeout /t 30 /nobreak >nul
wpeutil shutdown
exit /b 1

:winmint_finished
echo WinMint: already installed. Unplug the USB, then turn the laptop on.
echo WinMint: the internal disk was not changed.
wpeutil shutdown
exit /b 0

:winmint_see_applied
set HANDED=
set PROBEFAIL=
> "%WORK%\parts.txt" (
  echo select disk %TARGET%
  echo list partition
  echo exit
)
diskpart /s "%WORK%\parts.txt" > "%WORK%\partsout.txt"
for /f "usebackq tokens=1,2" %%a in ("%WORK%\partsout.txt") do if /i "%%a"=="Partition" if not "%%b"=="###" call :winmint_probe %%b
goto :eof

:winmint_probe
set N=%1
if defined HANDED goto :eof
if exist B:\ (
  set PROBEFAIL=1
  goto :eof
)
> "%WORK%\as%N%.txt" (
  echo select disk %TARGET%
  echo select partition %N%
  echo assign letter=B
  echo exit
)
diskpart /s "%WORK%\as%N%.txt" >nul
if not exist B:\ goto :eof
if exist B:\Windows\WinMint.applied set HANDED=1
> "%WORK%\rm%N%.txt" (
  echo select disk %TARGET%
  echo select partition %N%
  echo remove letter=B
  echo exit
)
diskpart /s "%WORK%\rm%N%.txt" >nul
goto :eof

rem Keeps a fixed disk as a candidate. BOOTDISK is the disk WinPE booted from.
rem PAYLOADDISK is the disk that holds install.wim. A Type USB line is an extra
rem skip for a second stick diskpart labels USB. Disk numbers stay discovered.
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
if defined BOOTDISK if "%N%"=="%BOOTDISK%" goto :eof
if defined PAYLOADDISK if "%N%"=="%PAYLOADDISK%" goto :eof
set BUSTYPE=
if defined WINMINT_BUS_READY if exist "%WORK%\buses.txt" (
  for /f "usebackq tokens=1,2" %%a in ("%WORK%\buses.txt") do if "%%a"=="%N%" set BUSTYPE=%%b
  if not defined BUSTYPE goto :eof
)
if /i "%BUSTYPE%"=="USB" goto :eof
if /i "%BUSTYPE%"=="SD" goto :eof
if /i "%BUSTYPE%"=="MMC" goto :eof
if /i "%BUSTYPE%"=="Virtual" goto :eof
if /i "%BUSTYPE%"=="FileBackedVirtual" goto :eof
if defined OVERRIDE (
  set HIT=
  for /f "usebackq delims=" %%l in ("%WORK%\d%N%.txt") do if not defined HIT call :winmint_text_has "%%l"
  if not defined HIT goto :eof
)
if defined TARGET (set EXTRA=1) else (set TARGET=%N%)
goto :eof

rem STORAGE_BUS_TYPE from WinMintApply.exe. A failed query refuses before any disk is cleaned.
:winmint_bus_types
set WINMINT_BUS_READY=
set WINMINT_BUS_FAIL=
"%~dp0WinMintApply.exe" --bus-types "%WORK%\buses.txt"
if errorlevel 1 set WINMINT_BUS_FAIL=1
if not defined WINMINT_BUS_FAIL set WINMINT_BUS_READY=1
goto :eof

rem Case-insensitive substring. The override path cannot call findstr.
:winmint_text_has
set "WINMINT_HAY=%~1"
if not defined WINMINT_HAY goto :eof
if not defined OVERRIDE goto :eof
call :winmint_fold WINMINT_HAY
set "WINMINT_NEED=%OVERRIDE%"
call :winmint_fold WINMINT_NEED
call set "WINMINT_FOLDED=%%WINMINT_HAY:%WINMINT_NEED%=%%"
if not "%WINMINT_FOLDED%"=="%WINMINT_HAY%" set HIT=1
goto :eof

:winmint_fold
setlocal EnableExtensions
set "S="
call set "S=%%%~1%%"
for %%a in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do call :winmint_fold_ch %%a
endlocal & set "%~1=%S%"
goto :eof

:winmint_fold_ch
if /i "%~1"=="a" set "S=%S:a=A%"
if /i "%~1"=="b" set "S=%S:b=B%"
if /i "%~1"=="c" set "S=%S:c=C%"
if /i "%~1"=="d" set "S=%S:d=D%"
if /i "%~1"=="e" set "S=%S:e=E%"
if /i "%~1"=="f" set "S=%S:f=F%"
if /i "%~1"=="g" set "S=%S:g=G%"
if /i "%~1"=="h" set "S=%S:h=H%"
if /i "%~1"=="i" set "S=%S:i=I%"
if /i "%~1"=="j" set "S=%S:j=J%"
if /i "%~1"=="k" set "S=%S:k=K%"
if /i "%~1"=="l" set "S=%S:l=L%"
if /i "%~1"=="m" set "S=%S:m=M%"
if /i "%~1"=="n" set "S=%S:n=N%"
if /i "%~1"=="o" set "S=%S:o=O%"
if /i "%~1"=="p" set "S=%S:p=P%"
if /i "%~1"=="q" set "S=%S:q=Q%"
if /i "%~1"=="r" set "S=%S:r=R%"
if /i "%~1"=="s" set "S=%S:s=S%"
if /i "%~1"=="t" set "S=%S:t=T%"
if /i "%~1"=="u" set "S=%S:u=U%"
if /i "%~1"=="v" set "S=%S:v=V%"
if /i "%~1"=="w" set "S=%S:w=W%"
if /i "%~1"=="x" set "S=%S:x=X%"
if /i "%~1"=="y" set "S=%S:y=Y%"
if /i "%~1"=="z" set "S=%S:z=Z%"
goto :eof

rem Called from the install retry. Each call is parsed afresh, so BOOTDISK and
rem WINMINT_BOOT_TAG set on an earlier try are visible here.
:winmint_find_install
if not defined BOOTDISK if not defined WINMINT_BOOT_TAG call :winmint_boot_disk
if not defined BOOTDISK if not defined WINMINT_BOOT_TAG (
  mountvol /e >nul 2>&1
  timeout /t 1 /nobreak >nul 2>&1
  goto :eof
)
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
  if not defined INSTALL if exist %%d:\usb-media.json if exist %%d:\sources\install.wim call :winmint_accept_install %%d
)
if not defined INSTALL (
  mountvol /e >nul 2>&1
  timeout /t 1 /nobreak >nul 2>&1
)
goto :eof

:winmint_boot_disk
if defined BOOTDISK goto :eof
if defined WINMINT_BOOT_TAG goto :eof
set BOOTLETTER=
for /f "tokens=1,2*" %%a in ('reg query HKLM\System\CurrentControlSet\Control /v PEBootRamdiskSourceDrive 2^>nul') do if /i "%%a"=="PEBootRamdiskSourceDrive" set "BOOTLETTER=%%c"
if not defined BOOTLETTER (
  set WINMINT_BOOT_TAG=1
  goto :eof
)
set "BOOTLETTER=%BOOTLETTER:~0,1%"
call :winmint_volume_disk %BOOTLETTER%
if defined VOLDISK set "BOOTDISK=%VOLDISK%"
goto :eof

rem Tag mode accepts the first volume whose disk number can be read. When the
rem boot disk is known, a volume on any other disk is left alone.
:winmint_accept_install
set "CANDIDATE=%~1"
call :winmint_volume_disk %CANDIDATE%
if not defined VOLDISK goto :eof
if defined BOOTDISK if /i not "%VOLDISK%"=="%BOOTDISK%" goto :eof
set "INSTALL=%CANDIDATE%"
set "PAYLOADDISK=%VOLDISK%"
goto :eof

:winmint_volume_disk
set VOLDISK=
set "VLETTER=%~1"
if not defined VLETTER goto :eof
if not exist "%TEMP%\winmint" mkdir "%TEMP%\winmint"
> "%TEMP%\winmint\vol%VLETTER%.txt" (
  echo select volume %VLETTER%
  echo detail volume
  echo exit
)
diskpart /s "%TEMP%\winmint\vol%VLETTER%.txt" > "%TEMP%\winmint\vol%VLETTER%out.txt"
call :winmint_parse_volume_disk "%TEMP%\winmint\vol%VLETTER%out.txt"
goto :eof

:winmint_parse_volume_disk
if not exist "%~1" goto :eof
set VOLDISK=
for /f "usebackq tokens=1,2,3" %%a in ("%~1") do (
  if /i "%%a"=="Disk" if not "%%b"=="###" if not defined VOLDISK set "VOLDISK=%%b"
  if "%%a"=="*" if /i "%%b"=="Disk" if not "%%c"=="###" set "VOLDISK=%%c"
)
goto :eof
