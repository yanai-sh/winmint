@echo off
REM Repo path: payload/scripts/SetupComplete.cmd
REM Image path: Windows\Setup\Scripts\SetupComplete.cmd
REM Machine setup: invoke published WinMint.Provisioning.exe --machine-setup
REM Binary path is filled when ImageServicing stages the AOT host (Smoke tickets 02–03).
REM No guest PowerShell — stamp-only Machine setup is ProvisioningSession entrypoint.
echo WinMint SetupComplete scaffold — Provisioning --machine-setup not wired yet.
exit /b 0
