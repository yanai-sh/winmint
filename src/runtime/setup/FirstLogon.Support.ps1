#Requires -Version 5.1

function Write-WinMintFirstLogonError {
    param([string]$Message)
    "$(Get-Date -Format 'o') $Message" | Out-File (Join-Path $logDir 'FirstLogon_errors.log') -Append
}

$setupScriptRoot = $PSScriptRoot
. (Join-Path $setupScriptRoot 'WindowsTerminal.Profiles.ps1')
. (Join-Path $setupScriptRoot 'FirstLogon.State.ps1')
. (Join-Path $setupScriptRoot 'FirstLogon.Host.ps1')
. (Join-Path $setupScriptRoot 'FirstLogon.Desktop.ps1')
. (Join-Path $setupScriptRoot 'FirstLogon.Terminal.ps1')
. (Join-Path $setupScriptRoot 'FirstLogon.Region.ps1')
. (Join-Path $setupScriptRoot 'FirstLogon.Cleanup.ps1')

