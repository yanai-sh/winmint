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

$markup = Format-WinMintLogMarkup -Level OK -Message 'badge-check'
if ($markup -notmatch 'on #98c379') { throw "expected One Half Dark OK badge markup, got: $markup" }
if ($markup -notmatch 'badge-check') { throw "expected message in markup, got: $markup" }
if ($markup -notmatch '│') { throw "expected rail glyph in markup, got: $markup" }
$plain = Format-WinMintLogPlainGlyph -Level INFO -Message 'plain-check'
if ($plain -notmatch '● plain-check') { throw "expected modern plain glyph, got: $plain" }

$themePath = Join-Path $RepositoryRoot 'src\runtime\WinMint.ConsoleTheme.ps1'
if (-not (Test-Path -LiteralPath $themePath)) { throw "missing shared theme: $themePath" }
$shared = Format-WinMintConsoleLineMarkup -Level INFO -Message 'shared-line' -SafeMessage 'shared-line'
if ($shared -notmatch 'on #61afef') { throw "expected shared RUN badge, got: $shared" }

$displayPath = Join-Path $RepositoryRoot 'src\runtime\image\Private\Console\Display.ps1'
$displayText = Get-Content -LiteralPath $displayPath -Raw
if ($displayText -notmatch 'LogVerbose \$Description') {
    throw 'Invoke-Action should LogVerbose when live status/progress is used (avoid double announce)'
}

Write-Host 'Assert-WinMintBuildLogChannels: OK'
