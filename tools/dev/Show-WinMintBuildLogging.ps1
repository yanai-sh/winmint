#Requires -Version 7.6
<#
.SYNOPSIS
  Demo Fluent Spectre build-log chrome (human console). Verbose file still written under output\.
.EXAMPLE
  pwsh -NoProfile -File tools\dev\Show-WinMintBuildLogging.ps1
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $RepositoryRoot 'src\runtime\image\WinMint.ps1')
Initialize-WinMintEngine -RepositoryRoot $RepositoryRoot
if (Get-Command Initialize-ConsoleUtf8ForSpectre -ErrorAction SilentlyContinue) {
    Initialize-ConsoleUtf8ForSpectre
}
Initialize-Spectre
Set-WinMintHumanConsoleMuted -Muted $false

# Opens sinks → session chrome panel (human + verbose path).
LogSection 'WinMint build logging demo'
Log 'Mounting image (demo)'
LogOK 'Edition selected: Windows 11 Pro'
LogWarn 'Driver pack missing a signature — continuing'
LogDry 'Would export install.wim (dry-run)'
LogVerbose 'Verbose line only with -Verbose; always in WinMint-Build.verbose.log'

# Invoke-Action: in an interactive TTY, live spinner replaces the RUN line (no double announce).
# Redirected hosts (CI/piped capture) fall back to a single RUN line — still one announce, not two.
$script:DryRun = $false
if (-not (Test-WinMintSpectreLiveUiAllowed)) {
    $dim = Get-WinMintConsoleTheme FgDim
    Write-WinMintHumanConsoleLine -Markup "[$dim]Live status/progress off here (redirected console) — Invoke-Action uses one RUN line.[/]" `
        -Plain 'Live status/progress off (redirected console).'
}
Invoke-Action 'Simulated DISM step (status)' {
    Start-Sleep -Milliseconds 700
}
Invoke-Action 'Simulated export progress' -SpectreProgressIndeterminate {
    if ($script:DismProgressCallback) {
        & $script:DismProgressCallback 35
        Start-Sleep -Milliseconds 200
        & $script:DismProgressCallback 70
        Start-Sleep -Milliseconds 200
        & $script:DismProgressCallback 100
    }
    else {
        Start-Sleep -Milliseconds 400
    }
}

try {
    1 / 0
}
catch {
    LogErr $_
}

LogErr 'Example string failure (non-fatal demo)'

$dim = Get-WinMintConsoleTheme FgDim
$green = Get-WinMintConsoleTheme Green
$cyan = Get-WinMintConsoleTheme Cyan
$blue = Get-WinMintConsoleTheme Blue
Write-WinMintLogSummaryPanel -Title 'Demo complete' -Rows @(
    [pscustomobject]@{ Item = "[$dim]Human[/]"; Value = "[$green]One Half Dark Spectre[/]" }
    [pscustomobject]@{ Item = "[$dim]File[/]"; Value = "[$cyan]$(Escape-WinMintSpectreMarkup (Get-WinMintBuildVerboseLogPath))[/]" }
    [pscustomobject]@{ Item = "[$dim]Theme[/]"; Value = "[$blue]$blue[/] [dim]·[/] rail + badges + panels" }
)
