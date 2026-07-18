#Requires -Version 7.6
<#
.SYNOPSIS
  Minimal self-check for dual-channel ISO build logging (human mute + verbose file).
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $RepositoryRoot 'src\runtime\image\WinMint.ps1')
Initialize-WinMintEngine -RepositoryRoot $RepositoryRoot

$out = Get-WinMintOutputDirectory
$verbosePath = Join-Path $out 'WinMint-Build.verbose.log'
$mirrorPath = Join-Path $out 'WinMint-Build.log'
Remove-Item -LiteralPath $verbosePath, $mirrorPath -ErrorAction SilentlyContinue
$script:WinMintBuildLogInit = $false
$script:WinMintBuildVerboseLogPath = $null
$script:WinMintBuildLogPath = $null

Set-WinMintHumanConsoleMuted -Muted $true
LogOK 'channel-check-muted'
if (-not (Test-Path -LiteralPath $verbosePath)) { throw "verbose log missing: $verbosePath" }
$mutedText = Get-Content -LiteralPath $verbosePath -Raw
if ($mutedText -notmatch 'OK channel-check-muted') { throw 'muted LogOK did not reach verbose file' }

$savedVerbose = $VerbosePreference
$VerbosePreference = 'SilentlyContinue'
try {
    LogVerbose 'channel-check-verbose-always'
}
finally {
    $VerbosePreference = $savedVerbose
}
$afterVerbose = Get-Content -LiteralPath $verbosePath -Raw
if ($afterVerbose -notmatch 'VERBOSE channel-check-verbose-always') {
    throw 'LogVerbose without -Verbose did not reach verbose file'
}

Set-WinMintHumanConsoleMuted -Muted $false
LogOK 'channel-check-human'
$final = Get-Content -LiteralPath $verbosePath -Raw
if ($final -notmatch 'OK channel-check-human') { throw 'unmuted LogOK missing from verbose file' }
$mirror = Get-Content -LiteralPath $mirrorPath -Raw
if ($mirror -notmatch 'OK channel-check-human') { throw 'mirror WinMint-Build.log missing LogOK line' }

Write-Host 'Assert-WinMintBuildLogChannels: OK'
