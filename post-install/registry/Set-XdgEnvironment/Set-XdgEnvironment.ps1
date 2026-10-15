#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Set the XDG base directories under this profile.
.DESCRIPTION
  Maintainer working tree. Not ready for anyone else to run.
  Windows PowerShell 5.1 and PowerShell 7. Run elevated.
  -DryRun prints each value and writes nothing.
#>
param([switch] $DryRun)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
    $PSNativeCommandUseErrorActionPreference = $false
}

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Registry.ps1')

Set-RegExpand 'HKCU:\Environment' 'XDG_CONFIG_HOME' '%USERPROFILE%\.config'
Set-RegExpand 'HKCU:\Environment' 'XDG_DATA_HOME' '%USERPROFILE%\.local\share'
Set-RegExpand 'HKCU:\Environment' 'XDG_STATE_HOME' '%USERPROFILE%\.local\state'
Set-RegExpand 'HKCU:\Environment' 'XDG_CACHE_HOME' '%USERPROFILE%\.cache'

if ($DryRun) {
    Write-Output 'dry-run: XDG environment not written.'
}
else {
    Write-Output 'XDG environment applied. Sign out and back in.'
}
