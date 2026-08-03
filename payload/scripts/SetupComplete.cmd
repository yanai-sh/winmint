@echo off
REM Repo path: payload/scripts/SetupComplete.cmd
REM Image path: Windows\Setup\Scripts\SetupComplete.cmd
REM Machine setup: invoke published Supervisor --machine-setup (non-zero on fail).
"%SystemRoot%\WinMint\Supervisor.exe" --machine-setup
if errorlevel 1 exit /b 1
