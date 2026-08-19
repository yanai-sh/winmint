#requires -Version 7.6
<#
.SYNOPSIS
  Visible host progress for Smoke/Apply. Own console — close it to stop watching, not the run.
#>
param(
    [Parameter(Mandatory)]
    [string] $Work
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$host.UI.RawUI.WindowTitle = "WinMint host watch — $Work"
Write-Host 'Close this window to stop watching. Apply/Smoke keep running.'
$apply = Join-Path $Work 'apply-status.txt'
$status = Join-Path $Work 'smoke-status.json'

while ($true) {
    Clear-Host
    Write-Host $host.UI.RawUI.WindowTitle
    Write-Host (Get-Date -Format 'HH:mm:ss')
    Write-Host ''
    Write-Host '== apply-status =='
    if (Test-Path -LiteralPath $apply) {
        Get-Content -LiteralPath $apply
    }
    else {
        Write-Host '(none yet)'
    }
    Write-Host ''
    Write-Host '== smoke-status =='
    if (Test-Path -LiteralPath $status) {
        Get-Content -LiteralPath $status
    }
    else {
        Write-Host '(none yet)'
    }
    $log = $null
    if (Test-Path -LiteralPath $apply) {
        foreach ($line in Get-Content -LiteralPath $apply) {
            if ($line.StartsWith('log=')) {
                $log = $line.Substring(4)
                break
            }
        }
    }
    if ($log -and (Test-Path -LiteralPath $log)) {
        Write-Host ''
        Write-Host "== $(Split-Path -Leaf $log) (tail) =="
        Get-Content -LiteralPath $log -Tail 25
    }
    Start-Sleep -Seconds 2
}
