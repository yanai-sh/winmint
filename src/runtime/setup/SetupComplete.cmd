@echo off
REM Runs once as SYSTEM after installation, before first user logon (see Microsoft Learn: SetupComplete.cmd).
REM Breadcrumb FIRST: prove Windows actually invoked this script. If this marker is
REM absent on the installed system, the serviced image's SetupComplete.cmd never ran
REM (e.g. a vanilla install.wim was applied) - a loud, file-level signal.
md "%ProgramData%\WinMint\Logs" 2>nul
echo SetupComplete.cmd fired %DATE% %TIME%> "%ProgramData%\WinMint\Logs\SetupComplete-cmd-fired.txt"
set "PS7=%ProgramFiles%\PowerShell\7\pwsh.exe"
if exist "%PS7%" (
  "%PS7%" -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%SystemRoot%\Setup\Scripts\SetupComplete.ps1"
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%SystemRoot%\Setup\Scripts\SetupComplete.ps1"
)
exit /b %ERRORLEVEL%
