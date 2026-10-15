#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Point known folders at the normal profile paths.
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

. (Join-Path $PSScriptRoot 'Registry.ps1')

$folders = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
Set-RegExpand $folders 'Desktop' '%USERPROFILE%\Desktop'
Set-RegExpand $folders 'Personal' '%USERPROFILE%\Documents'
Set-RegExpand $folders 'My Pictures' '%USERPROFILE%\Pictures'
Set-RegExpand $folders 'My Music' '%USERPROFILE%\Music'
Set-RegExpand $folders 'My Video' '%USERPROFILE%\Videos'
Set-RegExpand $folders 'Favorites' '%USERPROFILE%\Favorites'
Set-RegExpand $folders '{374DE290-123F-4565-9164-39C4925E467B}' '%USERPROFILE%\Downloads'
Set-RegExpand $folders '{F42EE2D3-909F-4907-8871-4C22FC0BF756}' '%USERPROFILE%\Documents'
Set-RegExpand $folders '{0DDD015D-B06C-45D5-8C4C-F59713854639}' '%USERPROFILE%\Pictures'
Set-RegExpand $folders '{A0C69A99-21C8-4671-8703-7934162FCF1D}' '%USERPROFILE%\Music'
Set-RegExpand $folders '{35286A68-3C57-41A1-BBB1-0EAE73D76C95}' '%USERPROFILE%\Videos'
Set-RegExpand $folders '{754AC886-DF64-4CBA-86B5-F7FBF4FBCEF5}' '%USERPROFILE%\Desktop'

if ($DryRun) {
    Write-Output 'dry-run: shell folders not written.'
}
else {
    Write-Output 'Shell folders applied. Sign out and back in.'
}
