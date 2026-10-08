#requires -Version 7.6
# Smoke status facade: converge (wait/handoff/NIC) + watch/status JSON/BMP.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'SmokeConverge.ps1')
. (Join-Path $PSScriptRoot 'SmokeWatchStatus.ps1')
