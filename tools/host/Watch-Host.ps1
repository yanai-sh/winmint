#requires -Version 7.6
<#
.SYNOPSIS
  Own-console host watch for Smoke, Check, or Apply. Close it to stop watching, not the run.
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('smoke', 'check', 'apply')]
    [string] $Kind,

    [string] $Work = '',
    [string] $Path = '',
    # Invoke-Smoke binds leftover or empty after it already stamped this run.
    # Unbound = standalone watch: leftover file id is prior.
    [string] $PriorRunId,
    [string] $MarkerPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $repoRoot 'tools/host/Write-WinMintHostProgress.ps1')

switch ($Kind) {
    'smoke' {
        . (Join-Path $repoRoot 'tools/vm/SmokeStatus.ps1')
        if ([string]::IsNullOrWhiteSpace($Work)) { $Work = Join-Path $repoRoot '.scratch\smoke' }
        $host.UI.RawUI.WindowTitle = "WinMint host watch — $Work"
        Write-Host 'Close this window to stop watching. Apply/Smoke keep running.'
        $apply = Join-Path $Work 'apply-status.txt'
        $status = Join-Path $Work 'smoke-status.json'
        if (-not $PSBoundParameters.ContainsKey('PriorRunId')) {
            $PriorRunId = ''
            if (Test-Path -LiteralPath $status -PathType Leaf) {
                try {
                    $PriorRunId = [string]((Get-Content -LiteralPath $status -Raw -Encoding utf8 | ConvertFrom-Json).runId)
                }
                catch { $PriorRunId = '' }
            }
        }
    }
    'check' {
        . (Join-Path $repoRoot 'tools/host/CheckStatus.ps1')
        if ([string]::IsNullOrWhiteSpace($Path)) {
            $Path = Join-Path $repoRoot '.scratch\check-status.json'
        }
        $host.UI.RawUI.WindowTitle = "WinMint check watch — $Path"
        Write-Host 'Close this window to stop watching. just check keeps running.'
    }
    'apply' {
        . (Join-Path $repoRoot 'tools/host/WinMintPaths.ps1')
        if ([string]::IsNullOrWhiteSpace($Work)) {
            $Work = Get-WinMintGateBWorkDirectory
        }
        $host.UI.RawUI.WindowTitle = "WinMint apply watch — $Work"
        Write-Host 'Close this window to stop watching. Apply keeps running.'
        $apply = Join-Path $Work 'apply-status.txt'
    }
}

if (-not [string]::IsNullOrWhiteSpace($MarkerPath)) {
    Set-Content -LiteralPath $MarkerPath -Value $PID -Encoding utf8
}

$doneTicks = 0
$ageSw = $null
$lastFp = ''
while ($true) {
    $verdict = ''
    $phase = ''
    $vmState = ''
    $heartbeat = ''
    $stallLeft = 0
    $wallLeft = 0
    $lastHost = ''
    $leaf = ''
    $applyStage = ''
    $logLeaf = ''
    $logTail = @()
    $format = @{ Title = $host.UI.RawUI.WindowTitle }

    if ($Kind -in @('smoke', 'apply')) {
        $snap = Read-WinMintApplyStatus -Path $apply
        if ($null -ne $snap) {
            $applyStage = [string]$snap.Stage
            if ($snap.Log -and (Test-Path -LiteralPath $snap.Log)) {
                $logLeaf = Split-Path -Leaf $snap.Log
                $rawTail = @(Get-Content -LiteralPath $snap.Log -Tail 40)
                $logTail = @(Select-WinMintWatchLogTail -Lines $rawTail -Count 8)
            }
        }
        $format.ApplyStage = $applyStage
        $format.LogLeaf = $logLeaf
        $format.LogTail = $logTail
    }

    if ($Kind -eq 'smoke') {
        $doc = $null
        if (Test-Path -LiteralPath $status) {
            try { $doc = Get-Content -LiteralPath $status -Raw -Encoding utf8 | ConvertFrom-Json } catch { $doc = $null }
        }
        $verdict = 'awaiting-run'
        if ($null -ne $doc) {
            $fp = [string]$doc.runId + '|' + [string]$doc.phase + '|' + [string]$doc.updatedAt + '|' +
                [string]$doc.vmState + '|' + [string]$doc.vhdFileSizeMB
            if ($fp -ne $lastFp) {
                $lastFp = $fp
                $ageSw = [Diagnostics.Stopwatch]::StartNew()
            }
            $age = if ($null -eq $ageSw) { 0 } else { [int]$ageSw.Elapsed.TotalSeconds }
            $vmState = if ($doc.PSObject.Properties.Name -contains 'vmState') { [string]$doc.vmState } else { '' }
            $vhdMb = if ($doc.PSObject.Properties.Name -contains 'vhdFileSizeMB') { [int]$doc.vhdFileSizeMB } else { 0 }
            $statusRunId = if ($doc.PSObject.Properties.Name -contains 'runId') { [string]$doc.runId } else { '' }
            $phase = [string]$doc.phase
            $verdict = Get-SmokeWatchVerdict -Phase $phase -VmState $vmState `
                -VhdFileSizeMB $vhdMb -StatusAgeSeconds $age -StatusRunId $statusRunId -PriorRunId $PriorRunId
            $heartbeat = if ($doc.PSObject.Properties.Name -contains 'heartbeat') { [string]$doc.heartbeat } else { '' }
            $stallLeft = if ($doc.PSObject.Properties.Name -contains 'stallMinutesLeft') { [int]$doc.stallMinutesLeft } else { 0 }
            $wallLeft = if ($doc.PSObject.Properties.Name -contains 'wallMinutesLeft') { [int]$doc.wallMinutesLeft } else { 0 }
            $lastHost = if ($doc.PSObject.Properties.Name -contains 'lastHostLine') { [string]$doc.lastHostLine } else { '' }
        }
        $format.Verdict = $verdict
        $format.Phase = $phase
        $format.VmState = $vmState
        $format.Heartbeat = $heartbeat
        $format.StallMinutesLeft = $stallLeft
        $format.WallMinutesLeft = $wallLeft
        $format.LastHostLine = $lastHost
    }
    elseif ($Kind -eq 'check') {
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
        $format.Verdict = $verdict
        $format.Phase = $phase
        $format.Leaf = $leaf
        $format.LastHostLine = $lastHost
    }

    Clear-Host
    Write-Host (Format-WinMintHostWatch @format)

    if ($Kind -ne 'apply' -and $verdict -eq 'done') {
        $doneTicks++
        if ($doneTicks -ge 3) { break }
    }
    else {
        $doneTicks = 0
    }
    Start-Sleep -Seconds 2
}
