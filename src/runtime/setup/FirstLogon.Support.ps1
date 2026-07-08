#Requires -Version 5.1

function Write-WinMintFirstLogonError {
    param([string]$Message)
    "$(Get-Date -Format 'o') $Message" | Out-File (Join-Path (Get-WinMintFirstLogonContext).LogDir 'FirstLogon_errors.log') -Append
}

$setupScriptRoot = $PSScriptRoot
. (Join-Path $setupScriptRoot 'WinMint.Runtime.Common.ps1')
. (Join-Path $setupScriptRoot 'WinMint.RuntimeState.ps1')
. (Join-Path $setupScriptRoot 'FirstLogon.Context.ps1')
. (Join-Path $setupScriptRoot 'FirstLogon.State.ps1')
. (Join-Path $setupScriptRoot 'WinMint.Diagnostics.ps1')
. (Join-Path $setupScriptRoot 'WindowsTerminal.Profiles.ps1')
. (Join-Path $setupScriptRoot 'FirstLogon.Host.ps1')
. (Join-Path $setupScriptRoot 'WinMintSetupShell.Status.ps1')
. (Join-Path $setupScriptRoot 'ProvisioningGuard.ps1')
. (Join-Path $setupScriptRoot 'FirstLogon.Desktop.ps1')
. (Join-Path $setupScriptRoot 'FirstLogon.Region.ps1')
. (Join-Path $setupScriptRoot 'FirstLogon.Cleanup.ps1')

