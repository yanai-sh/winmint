#requires -Version 7.6
<#
.SYNOPSIS
  Own-console apply-status watch. Close this window to stop watching, not Apply.
#>
param(
    [string] $Work
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $repoRoot 'tools/host/WinMintPaths.ps1')
. (Join-Path $repoRoot 'tools/host/Write-WinMintHostProgress.ps1')

if ([string]::IsNullOrWhiteSpace($Work)) {
    $Work = Get-WinMintGateBWorkDirectory
}

$host.UI.RawUI.WindowTitle = "WinMint apply watch — $Work"
Write-Host 'Close this window to stop watching. Apply keeps running.'

$apply = Join-Path $Work 'apply-status.txt'
while ($true) {
    $snap = Read-WinMintApplyStatus -Path $apply
    $stage = ''
    $logLeaf = ''
    $logTail = @()
    if ($null -ne $snap) {
        $stage = [string]$snap.Stage
        if ($snap.Log -and (Test-Path -LiteralPath $snap.Log)) {
            $logLeaf = Split-Path -Leaf $snap.Log
            $logTail = @(Get-Content -LiteralPath $snap.Log -Tail 8)
        }
    }

    Clear-Host
    Write-Host (Format-WinMintHostWatch -Title $host.UI.RawUI.WindowTitle `
            -ApplyStage $stage -LogLeaf $logLeaf -LogTail $logTail)

    Start-Sleep -Seconds 2
}
