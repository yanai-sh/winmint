@echo off
rem Tiny launcher for setup-pass PowerShell scripts. The Microsoft-Windows-Deployment
rem RunSynchronousCommand <Path> field has a length limit (~259 chars); an inline
rem "if exist pwsh (...) else (...)" conditional exceeds it and makes Windows Setup
rem reject the whole answer file in the specialize pass (0x80220005). Keeping the
rem pwsh7-with-Windows-PowerShell-fallback logic here lets the answer file reference
rem a short path instead. Usage: RunSetupScript.cmd <ScriptFileName.ps1>
setlocal
set "PS7=C:\Program Files\PowerShell\7\pwsh.exe"
set "TARGET=C:\Windows\Setup\Scripts\%~1"
if exist "%PS7%" (
    "%PS7%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%TARGET%"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%TARGET%"
)
exit /b %ERRORLEVEL%
