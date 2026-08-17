@echo off
REM Repo path: payload/scripts/SetupComplete.cmd
REM Image path: Windows\Setup\Scripts\SetupComplete.cmd
REM Setup launches this via cmd.exe with a window. Supervisor --machine-setup
REM ShowWindow(SW_HIDE) on that inherited console, then reserved-storage DISM as SYSTEM.
REM Keep this process tree so Hide can close the Setup console. SYSTEM only (not user IL).
"%SystemRoot%\WinMint\Supervisor.exe" --machine-setup
if errorlevel 1 exit /b 1
