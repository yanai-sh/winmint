#requires -Version 7.6
<#
.SYNOPSIS
  Own-console Check status watch. Close this window to stop watching, not the gate.
  Exits a few ticks after Get-CheckWatchVerdict returns done (passed/failed).
#>
param(
    [string] $Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
if ([string]::IsNullOrWhiteSpace($Path)) {
    $Path = Join-Path $repoRoot '.scratch\check-status.json'
}
. (Join-Path $repoRoot 'tools/host/CheckStatus.ps1')
. (Join-Path $repoRoot 'tools/host/Write-WinMintHostProgress.ps1')

$host.UI.RawUI.WindowTitle = "WinMint check watch — $Path"
Write-Host 'Close this window to stop watching. just check keeps running.'

$doneTicks = 0
while ($true) {
    $phase = ''
    $leaf = ''
    $lastHost = ''
    $verdict = 'continue'
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try {
            $doc = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
            $phase = [string]$doc.phase
            $leaf = if ($doc.PSObject.Properties.Name -contains 'leaf') { [string]$doc.leaf } else { '' }
            $lastHost = if ($doc.PSObject.Properties.Name -contains 'lastHostLine') { [string]$doc.lastHostLine } else { '' }
            $verdict = Get-CheckWatchVerdict -Phase $phase
        }
        catch {
            $verdict = 'continue'
        }
    }

    Clear-Host
    Write-Host (Format-WinMintHostWatch -Title $host.UI.RawUI.WindowTitle `
            -Verdict $verdict -Phase $phase -Leaf $leaf -LastHostLine $lastHost)

    if ($verdict -eq 'done') {
        $doneTicks++
        if ($doneTicks -ge 3) { break }
    }
    else {
        $doneTicks = 0
    }
    Start-Sleep -Seconds 2
}
