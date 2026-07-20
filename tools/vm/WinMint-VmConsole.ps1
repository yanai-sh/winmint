#Requires -Version 7.6
# Shared console helpers for VM acceptance/build automation.
# Dot-source from tools/vm/*.ps1 — not a standalone entrypoint.
. (Join-Path $PSScriptRoot 'WinMint-VmAcceptanceProfile.ps1')
. (Join-Path $PSScriptRoot 'Get-WinMintVmGuestWaitSnapshot.ps1')

$libRoot = Join-Path $PSScriptRoot 'lib'
. (Join-Path $libRoot 'VmLog.ps1')
. (Join-Path $libRoot 'VmObserve.ps1')
. (Join-Path $libRoot 'VmGuest.ps1')
. (Join-Path $libRoot 'VmFingerprint.ps1')
. (Join-Path $libRoot 'VmEvidence.ps1')
. (Join-Path $libRoot 'VmShellDesktopEvidence.ps1')
. (Join-Path $libRoot 'VmSetupCompleteEvidence.ps1')
