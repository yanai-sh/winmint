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
goto :winmint_start

:winmint_init_pe
echo WinMint: initializing Windows PE...
rem A missing unattend must not fall back to bare wpeinit. That wait is the blue screen.
if not exist "%~dp0wpeinit.xml" (
  echo WinMint: wpeinit.xml is missing. Network stays off.
  goto :eof
)
wpeinit -unattend:"%~dp0wpeinit.xml"
goto :eof

:winmint_start
rem The payload is often mounted already. A bare wpeinit turns the network on and
rem waits on Wi-Fi DHCP, so the blue desktop never reaches shutdown.
set INSTALL=
set BOOTDISK=
set PAYLOADDISK=
set WINMINT_BOOT_TAG=
set REINSTALL=
set SEEN=
call :winmint_see_payload nowait
if defined SEEN if not exist "%SEEN%:\winmint-boot-probe.txt" if not exist "%SEEN%:\winmint-reinstall.txt" if not exist "%SEEN%:\winmint-applied.txt" if not exist "%SEEN%:\winmint-install.txt" (
  echo WinMint: install file is not present.
  echo WinMint: the internal disk was not changed.
  wpeutil shutdown
  exit /b 0
)
set SEEN=
call :winmint_init_pe
set "PATH=%SystemRoot%\System32;%PATH%"
rem Microsoft: wpeutil UpdateBootInfo records the volume WinPE booted from.
rem PEBootRamdiskSourceDrive is that letter. detail volume turns it into a disk
rem number. That number is the stick, including when diskpart's Type line is
rem SCSI, SATA, NVMe, or RAID. A Type USB line is only an extra skip for a
rem second stick that diskpart does label USB.
wpeutil UpdateBootInfo
for /L %%i in (1,1,10) do if not defined SEEN call :winmint_see_payload
if not defined SEEN (
  echo WinMint: install.wim not found on any drive
  exit /b 1
)
set INSTALL=%SEEN%
rem Markers stay on this letter. diskpart starts only after the install file is present.
if exist "%INSTALL%:\winmint-boot-probe.txt" goto :winmint_boot_probe
rem A second boot of this USB must not erase the disk. A finished install turns the PC off.
rem The applied marker must not hide a request to put the previous EFI files back.
if not exist "%INSTALL%:\winmint-reinstall.txt" if exist "%INSTALL%:\winmint-applied.txt" if not exist "%INSTALL%:\winmint-restore-esp.txt" goto :winmint_finished
if not exist "%INSTALL%:\winmint-install.txt" (
  echo WinMint: install file is not present.
  echo WinMint: the internal disk was not changed.
  wpeutil shutdown
  exit /b 0
)
for /L %%i in (1,1,10) do if not defined PAYLOADDISK if not defined WINMINT_BOOT_TAG call :winmint_find_install
if defined WINMINT_BOOT_TAG (
  echo WinMint: boot disk was not recorded. The internal disk was not changed.
  exit /b 1
)
if not defined PAYLOADDISK (
  echo WinMint: install.wim not found on the boot disk
  exit /b 1
)
if exist "%INSTALL%:\winmint-reinstall.txt" (
  set REINSTALL=1
  echo WinMint: reinstall requested. The Windows partition will be replaced.
)
echo WinMint: boot disk %BOOTDISK%, install.wim on %INSTALL%:
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
call :winmint_audit_buses
if defined WINMINT_BUS_FAIL (
  echo WinMint: could not read disk bus types
  exit /b 1
)
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
  echo Put one whole model line in %INSTALL%:\winmint-target-disk.txt and reboot.
  exit /b 1
)
set RESUME=
rem winmint-format-started without the applied marker resumes. A finished install plus reinstall replaces Windows again.
if exist "%INSTALL%:\winmint-format-started.txt" if not exist "%INSTALL%:\winmint-applied.txt" set RESUME=1
if not defined REINSTALL if not defined RESUME if not exist "%INSTALL%:\winmint-restore-esp.txt" call :winmint_see_applied
if defined HANDED goto :winmint_finished
if defined PROBEFAIL (
  echo WinMint: could not check the internal disk for an existing install. Refusing to erase.
  exit /b 1
)
echo WinMint: erasing disk %TARGET%
if not defined BOOTDISK (
  echo WinMint: boot disk was not recorded. The internal disk was not changed.
  exit /b 1
)
call :winmint_map_parts
if defined PART_FAIL (
  echo WinMint: a partition type could not be read. The internal disk was not changed.
  exit /b 1
)
if not defined EFI_PART (
  echo WinMint: EFI partition was not found. The internal disk was not changed.
  exit /b 1
)
if not "%WIN_COUNT%"=="1" if defined RESUME if "%WIN_COUNT%"=="0" if "%BASIC_COUNT%"=="1" (
  set WIN_PART=%BASIC_PART%
  set WIN_COUNT=1
)
if not "%WIN_COUNT%"=="1" (
  echo WinMint: the Windows partition was not identified. The internal disk was not changed.
  exit /b 1
)
set EFILETTER=
set WINLETTER=
set RECLETTER=
call :winmint_take_letter EFILETTER
call :winmint_take_letter WINLETTER
call :winmint_take_letter RECLETTER
if defined PART_FAIL (
  echo WinMint: no free drive letter. The internal disk was not changed.
  exit /b 1
)
call :winmint_assign %EFI_PART% %EFILETTER%
if errorlevel 1 exit /b 1
call :winmint_require_target %EFILETTER%
if errorlevel 1 exit /b 1
if exist "%INSTALL%:\winmint-restore-esp.txt" (
  call :winmint_restore_esp
  if errorlevel 1 exit /b 1
  del /f /q "%INSTALL%:\winmint-restore-esp.txt"
  echo WinMint: previous EFI files were restored.
  goto :winmint_unplug
)
call :winmint_assign %WIN_PART% %WINLETTER%
if errorlevel 1 exit /b 1
call :winmint_require_target %WINLETTER%
if errorlevel 1 exit /b 1
"%~dp0WinMintApply.exe" --image-fits "%INSTALL%:\sources\install.wim" %WINLETTER%
set FIT=%ERRORLEVEL%
if "%FIT%"=="2" (
  echo WinMint: the Windows partition is too small. The internal disk was not changed.
  exit /b 1
)
if not "%FIT%"=="0" (
  echo WinMint: could not compare the image to the Windows partition. The internal disk was not changed.
  exit /b 1
)
rem EFI files are copied to winmint-esp-backup before the Windows partition is formatted.
call :winmint_backup_esp
if errorlevel 1 (
  echo WinMint: EFI backup failed. The internal disk was not changed.
  exit /b 1
)
if defined RESUME goto :winmint_resume
> "%TEMP%\winmint-status.txt" echo Formatting the Windows partition.
> "%TEMP%\winmint-format-started.txt" echo formatted
> "%INSTALL%:\winmint-format-started.txt" echo formatted
call :winmint_format_windows
if errorlevel 1 exit /b 1
goto :winmint_apply

:winmint_resume
if exist "%WINLETTER%:\Windows\System32\config\SYSTEM" (
  if exist "%INSTALL%:\winmint-boot-files.txt" goto :winmint_lab
  goto :winmint_bcd
)

:winmint_apply
> "%TEMP%\winmint-status.txt" echo Applying Windows.
echo WinMint: applying install.wim Index:1 to %WINLETTER%:\...
dism /English /Apply-Image /ImageFile:%INSTALL%:\sources\install.wim /Index:1 /ApplyDir:%WINLETTER%:\
if errorlevel 1 (
  echo WinMint: dism Apply-Image failed
  call :winmint_restore_esp
  exit /b 1
)

:winmint_bcd
> "%TEMP%\winmint-status.txt" echo Writing boot files.
rem The applied image's bcdboot knows /offline /bootex. WinPE's copy may not.
rem /s still targets the internal EFI partition. /offline /bootex selects the
rem Windows UEFI CA 2023 boot manager. Surface rejects the 2011 manager.
set BCDBOOT=%WINLETTER%:\Windows\System32\bcdboot.exe
if not exist "%BCDBOOT%" set BCDBOOT=bcdboot
"%BCDBOOT%" %WINLETTER%:\Windows /s %EFILETTER%: /f UEFI /offline /bootex
if errorlevel 1 (
  echo WinMint: bcdboot /offline /bootex failed. The 2011 UEFI CA boot manager is not a fallback.
  call :winmint_restore_esp
  exit /b 1
)
echo WinMint boot files> "%INSTALL%:\winmint-boot-files.txt"
del /f /q "%INSTALL%:\winmint-reinstall.txt"

:winmint_lab
if exist "%INSTALL%:\OobeUnattend.xml" (
  if not exist %WINLETTER%:\Windows\Panther mkdir %WINLETTER%:\Windows\Panther
  copy /Y "%INSTALL%:\OobeUnattend.xml" %WINLETTER%:\Windows\Panther\unattend.xml
)
echo WinMint: configuring LabConfig bypasses in offline SYSTEM hive...
reg load HKLM\WinMintApply %WINLETTER%:\Windows\System32\config\SYSTEM
if errorlevel 1 (
  echo WinMint: reg load SYSTEM failed
  exit /b 1
)
reg add HKLM\WinMintApply\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f
reg add HKLM\WinMintApply\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f
reg add HKLM\WinMintApply\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f
reg unload HKLM\WinMintApply
if errorlevel 1 (
  echo WinMint: reg unload SYSTEM failed
  exit /b 1
)
echo WinMint apply complete> "%INSTALL%:\winmint-applied.txt"
echo WinMint apply complete> "%WINLETTER%:\Windows\WinMint.applied"
echo WinMint: registering Windows RE...
if not exist %WINLETTER%:\Windows\System32\Recovery\Winre.wim (
  echo WinMint: Winre.wim missing from the applied image. Boot files are in place.
  goto :winmint_unplug
)
set WINRE_BYTES=
for %%f in ("%WINLETTER%:\Windows\System32\Recovery\Winre.wim") do set WINRE_BYTES=%%~zf
set WINRE_MB=
set SHRINK_MB=
set /a WINRE_MB=(WINRE_BYTES+1048575)/1048576
set /a SHRINK_MB=WINRE_MB+250
if not defined SHRINK_MB (
  echo WinMint: Winre.wim size could not be read. Boot files are in place.
  goto :winmint_unplug
)
rem Shrink Windows by the wim size plus 250 MB. An existing recovery partition is left in place.
> "%WORK%\winre.txt" (
  echo select disk %TARGET%
  echo select volume %WINLETTER%
  echo shrink desired=%SHRINK_MB%
  echo create partition primary
  echo format quick fs=ntfs label=Recovery
  echo assign letter=%RECLETTER%
  echo set id=de94bba4-06d1-4d40-a16a-bfd50179d6ac
  echo gpt attributes=0x8000000000000001
  echo exit
)
diskpart /s "%WORK%\winre.txt"
if errorlevel 1 (
  echo WinMint: recovery setup failed. Boot files are in place.
  goto :winmint_unplug
)
if not exist %RECLETTER%:\ (
  echo WinMint: recovery setup failed. Boot files are in place.
  goto :winmint_unplug
)
if not exist %RECLETTER%:\Recovery\WindowsRE mkdir %RECLETTER%:\Recovery\WindowsRE
xcopy /h /y "%WINLETTER%:\Windows\System32\Recovery\Winre.wim" "%RECLETTER%:\Recovery\WindowsRE\"
if errorlevel 1 (
  echo WinMint: recovery setup failed. Boot files are in place.
  goto :winmint_unplug
)
set REAGENTC=%WINLETTER%:\Windows\System32\reagentc.exe
set BCDEDIT=%WINLETTER%:\Windows\System32\bcdedit.exe
if not exist "%REAGENTC%" (
  echo WinMint: reagentc.exe missing from the applied image. Boot files are in place.
  goto :winmint_unplug
)
if not exist "%BCDEDIT%" (
  echo WinMint: bcdedit.exe missing from the applied image. Boot files are in place.
  goto :winmint_unplug
)
set OSGUID=
for /f "tokens=1,2" %%a in ('"%BCDEDIT%" /store %EFILETTER%:\EFI\Microsoft\Boot\BCD /enum {default} /v') do if /i "%%a"=="identifier" if not defined OSGUID set OSGUID=%%b
set WINRE_GUID_OK=
if defined OSGUID if "%OSGUID:~0,1%"=="{" if "%OSGUID:~9,1%"=="-" set WINRE_GUID_OK=1
if not defined WINRE_GUID_OK (
  echo WinMint: bcdedit did not return the Windows boot identifier. Boot files are in place.
  goto :winmint_unplug
)
"%REAGENTC%" /setreimage /path %RECLETTER%:\Recovery\WindowsRE /target %WINLETTER%:\Windows
if errorlevel 1 (
  echo WinMint: reagentc /setreimage failed. Boot files are in place.
  goto :winmint_unplug
)
"%REAGENTC%" /enable /osguid %OSGUID%
if errorlevel 1 (
  echo WinMint: reagentc /enable failed. Boot files are in place.
  goto :winmint_unplug
)
echo WinMint: apply complete. Rebooting into installed Windows...
wpeutil reboot
exit /b 0

:winmint_unplug
> "%TEMP%\winmint-status.txt" echo Unplug the USB, then turn the laptop on.
echo WinMint: Unplug the USB, then turn the laptop on.
timeout /t 30 /nobreak >nul
wpeutil shutdown
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
goto :winmint_unplug

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

:winmint_map_parts
set EFI_PART=
set WIN_PART=
set WIN_COUNT=0
set BASIC_PART=
set BASIC_COUNT=0
set PART_FAIL=
> "%WORK%\map.txt" (
  echo select disk %TARGET%
  echo list partition
  echo exit
)
diskpart /s "%WORK%\map.txt" > "%WORK%\mapout.txt"
for /f "usebackq tokens=1,2" %%a in ("%WORK%\mapout.txt") do if /i "%%a"=="Partition" if not "%%b"=="###" call :winmint_class_part %%b
goto :eof

:winmint_class_part
if defined PART_FAIL goto :eof
set N=%1
> "%WORK%\class.txt" (
  echo select disk %TARGET%
  echo select partition %N%
  echo detail partition
  echo exit
)
diskpart /s "%WORK%\class.txt" > "%WORK%\classout.txt"
set GUID=
for /f "usebackq tokens=1,2,3" %%a in ("%WORK%\classout.txt") do if /i "%%a"=="Type" if not defined GUID set GUID=%%c
if not defined GUID (
  set PART_FAIL=1
  goto :eof
)
if /i "%GUID%"=="c12a7328-f81f-11d2-ba4b-00a0c93ec93b" (
  if defined EFI_PART (
    set PART_FAIL=1
  ) else (
    set EFI_PART=%N%
  )
  goto :eof
)
if /i not "%GUID%"=="ebd0a0a2-b9e5-4433-87c0-68b6b72699c7" goto :eof
set /a BASIC_COUNT+=1
set BASIC_PART=%N%
call :winmint_mount_windows %N%
goto :eof

:winmint_mount_windows
set N=%1
set TRYLETTER=
for %%L in (V U T) do if not defined TRYLETTER if not exist %%L:\ set TRYLETTER=%%L
if not defined TRYLETTER (
  set PART_FAIL=1
  goto :eof
)
call :winmint_assign %N% %TRYLETTER%
if errorlevel 1 goto :eof
if exist %TRYLETTER%:\Windows\System32 (
  set /a WIN_COUNT+=1
  set WIN_PART=%N%
)
> "%WORK%\unmount.txt" (
  echo select disk %TARGET%
  echo select partition %N%
  echo remove letter=%TRYLETTER%
  echo exit
)
diskpart /s "%WORK%\unmount.txt" >nul
goto :eof

:winmint_take_letter
set TAKE=
for %%L in (S W R V U T) do if not defined TAKE call :winmint_letter_free %%L
if not defined TAKE (
  set PART_FAIL=1
  goto :eof
)
set %~1=%TAKE%
goto :eof

:winmint_letter_free
if exist %1:\ goto :eof
if /i "%1"=="%EFILETTER%" goto :eof
if /i "%1"=="%WINLETTER%" goto :eof
if /i "%1"=="%RECLETTER%" goto :eof
set TAKE=%1
goto :eof

:winmint_assign
set APART=%~1
set ALETTER=%~2
> "%WORK%\assign.txt" (
  echo select disk %TARGET%
  echo select partition %APART%
  echo assign letter=%ALETTER%
  echo exit
)
diskpart /s "%WORK%\assign.txt"
if errorlevel 1 exit /b 1
if not exist %ALETTER%:\ exit /b 1
exit /b 0

:winmint_require_target
call :winmint_volume_disk %1
if not defined VOLDISK exit /b 1
if /i not "%VOLDISK%"=="%TARGET%" (
  echo WinMint: letter %1 is not on the target disk.
  exit /b 1
)
exit /b 0

:winmint_backup_esp
if exist "%INSTALL%:\winmint-esp-backup\EFI\Microsoft\Boot\BCD" exit /b 0
mkdir "%INSTALL%:\winmint-esp-backup" 2>nul
xcopy /e /h /k /y /i "%EFILETTER%:\*" "%INSTALL%:\winmint-esp-backup\"
if errorlevel 1 exit /b 1
if not exist "%INSTALL%:\winmint-esp-backup\EFI\Microsoft\Boot\BCD" exit /b 1
exit /b 0

:winmint_restore_esp
> "%TEMP%\winmint-status.txt" echo Restoring previous boot files.
echo WinMint: restoring previous EFI files.
if not exist "%INSTALL%:\winmint-esp-backup\EFI\Microsoft\Boot\BCD" (
  echo WinMint: EFI backup is missing.
  exit /b 1
)
xcopy /e /h /k /y /i "%INSTALL%:\winmint-esp-backup\*" "%EFILETTER%:\" >nul
if errorlevel 1 (
  echo WinMint: EFI restore failed.
  exit /b 1
)
exit /b 0

:winmint_format_windows
rem noerr: an already-online disk returns an error. A disk that stays offline fails the format below.
> "%WORK%\fmt.txt" (
  echo select disk %TARGET%
  echo online disk noerr
  echo attributes disk clear readonly noerr
  echo select partition %WIN_PART%
  echo format quick fs=ntfs label=Windows
  echo assign letter=%WINLETTER%
  echo exit
)
echo WinMint: formatting the Windows partition on disk %TARGET%...
diskpart /s "%WORK%\fmt.txt"
if errorlevel 1 (
  echo WinMint: diskpart failed
  exit /b 1
)
call :winmint_require_target %WINLETTER%
if errorlevel 1 exit /b 1
exit /b 0

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

rem STORAGE_BUS_TYPE from WinMintApply.exe. A failed query refuses before a disk is chosen.
:winmint_bus_types
set WINMINT_BUS_READY=
set WINMINT_BUS_FAIL=
"%~dp0WinMintApply.exe" --bus-types "%WORK%\buses.txt"
if errorlevel 1 set WINMINT_BUS_FAIL=1
if not defined WINMINT_BUS_FAIL set WINMINT_BUS_READY=1
goto :eof

rem One whole detail-disk line, case-insensitive. A short string matches nothing. The override path cannot call findstr.
:winmint_text_has
set "WINMINT_HAY=%~1"
if not defined WINMINT_HAY goto :eof
if not defined OVERRIDE goto :eof
call :winmint_fold WINMINT_HAY
set "WINMINT_NEED=%OVERRIDE%"
call :winmint_fold WINMINT_NEED
if "%WINMINT_HAY%"=="%WINMINT_NEED%" set HIT=1
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

rem Payload letter only. No diskpart. The boot-disk check is winmint_find_install, after the install file.
:winmint_see_payload
for %%d in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
  if not defined SEEN if exist %%d:\usb-media.json if exist %%d:\sources\install.wim set "SEEN=%%d"
  if exist %%d:\usb-media.json if exist %%d:\sources\install.wim if exist %%d:\winmint-boot-probe.txt set "SEEN=%%d"
)
rem nowait: the unarmed check looks once. A missing letter must not sit on timeout before wpeinit.
if not defined SEEN if not "%~1"=="nowait" (
  mountvol /e >nul 2>&1
  timeout /t 1 /nobreak >nul 2>&1
)
goto :eof

rem Called from the install retry. A missing boot letter is a refusal, not a guess.
:winmint_find_install
if defined WINMINT_BOOT_TAG goto :eof
if not defined BOOTDISK call :winmint_boot_disk
if defined WINMINT_BOOT_TAG goto :eof
if not defined BOOTDISK (
  mountvol /e >nul 2>&1
  timeout /t 1 /nobreak >nul 2>&1
  goto :eof
)
if not defined INSTALL goto :eof
call :winmint_accept_install %INSTALL%
if not defined PAYLOADDISK (
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

rem The payload must sit on the recorded boot disk. A missing boot disk is refused.
:winmint_accept_install
set "CANDIDATE=%~1"
if not defined BOOTDISK goto :eof
call :winmint_volume_disk %CANDIDATE%
if not defined VOLDISK goto :eof
if /i not "%VOLDISK%"=="%BOOTDISK%" goto :eof
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
set VOLHITS=0
set LASTDISK=
for /f "usebackq tokens=1,2,3" %%a in ("%~1") do (
  if "%%a"=="*" if /i "%%b"=="Disk" if not "%%c"=="###" (
    set /a VOLHITS+=1
    set "LASTDISK=%%c"
  )
)
if "%VOLHITS%"=="1" set "VOLDISK=%LASTDISK%"
goto :eof

:winmint_audit_buses
if not exist "%WORK%\buses.txt" goto :eof
for /f "usebackq tokens=1,2" %%a in ("%LIST%") do if /i "%%a"=="Disk" if not "%%b"=="###" call :winmint_need_bus %%b
goto :eof

:winmint_need_bus
set FOUND=
for /f "usebackq tokens=1,2" %%a in ("%WORK%\buses.txt") do if "%%a"=="%1" set FOUND=1
if not defined FOUND set WINMINT_BUS_FAIL=1
goto :eof
