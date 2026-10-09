#requires -Version 7.6
<#
.SYNOPSIS
  Attach host Watch (smoke/apply) in the current console via Start-WinMintHostConsole -Here.
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('smoke', 'apply')]
    [string] $Kind,

    [string] $Work = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'WinMintHostConsole.ps1')
$pwshExe = (Get-Command pwsh.exe -ErrorAction Stop).Source
[void](Start-WinMintHostConsole -Here -RepoRoot $repoRoot -Work $Work -Kind $Kind `
    -MarkerPath '' -PwshExe $pwshExe)
