#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Write one HKLM or HKCU value with reg.exe.
.DESCRIPTION
  Maintainer working tree. Not ready for anyone else to run.
  Windows PowerShell 5.1 and PowerShell 7. Run elevated.
  HKLM and HKCU only. A second run writes the same value.
  -DryRun prints the value and writes nothing.
  Access denied is left unchanged.
#>
param(
    [Parameter(Mandatory)][string] $Path,
    [Parameter(Mandatory)][string] $Name,
    [Parameter(Mandatory)][string] $Type,
    [Parameter(Mandatory)][string] $Data,
    [switch] $DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
    $PSNativeCommandUseErrorActionPreference = $false
}

if ($DryRun) {
    Write-Output "dry-run: $Path $Name = $Data"
    return
}

if ($Path -notmatch '^(HKLM|HKCU):\\(.+)$') {
    throw "Unsupported registry path: $Path"
}

$regPath = $Matches[1] + '\' + $Matches[2]
$reg = Join-Path $env:SystemRoot 'System32\reg.exe'
# Redirected native stderr ends the script on Windows PowerShell 5.1 while Stop is in effect.
$ErrorActionPreference = 'Continue'
$output = & $reg add $regPath /v $Name /t $Type /d $Data /f 2>&1 | ForEach-Object { "$_" }
if ($LASTEXITCODE -eq 0) {
    return
}

$text = (@($output) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join ' '
if ($text -match 'Access is denied') {
    Write-Output "left unchanged: $regPath $Name"
    return
}

throw "Could not set $regPath $Name ($LASTEXITCODE). $text"
