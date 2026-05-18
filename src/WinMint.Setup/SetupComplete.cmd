@echo off
REM Runs once as SYSTEM after installation, before first user logon (see Microsoft Learn: SetupComplete.cmd).
set "PS7=%ProgramFiles%\PowerShell\7\pwsh.exe"
if exist "%PS7%" (
  "%PS7%" -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%SystemRoot%\Setup\Scripts\SetupComplete.ps1"
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%SystemRoot%\Setup\Scripts\SetupComplete.ps1"
)
exit /b %ERRORLEVEL%
