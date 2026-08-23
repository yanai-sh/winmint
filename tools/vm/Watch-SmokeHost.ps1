#requires -Version 7.6
<#
.SYNOPSIS
  Visible host progress for Smoke/Apply. Own console — close it to stop watching, not the run.
  Exits a few ticks after Get-SmokeWatchVerdict returns done (green/failed/assert).
#>
param(
    [Parameter(Mandatory)]
    [string] $Work,

    # Invoke-Smoke binds leftover or empty after it already stamped this run.
    # Unbound = standalone watch: leftover file id is prior.
    [string] $PriorRunId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$host.UI.RawUI.WindowTitle = "WinMint host watch — $Work"
Write-Host 'Close this window to stop watching. Apply/Smoke keep running.'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $repoRoot 'tools/vm/SmokeStatus.ps1')
. (Join-Path $repoRoot 'tools/host/Write-WinMintHostProgress.ps1')

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

$doneTicks = 0
while ($true) {
    $applyStage = ''
    $log = $null
    if (Test-Path -LiteralPath $apply) {
        foreach ($line in Get-Content -LiteralPath $apply) {
            if ($line.StartsWith('stage=')) { $applyStage = $line.Substring(6) }
            if ($line.StartsWith('log=')) { $log = $line.Substring(4) }
        }
    }

    $doc = $null
    if (Test-Path -LiteralPath $status) {
        try { $doc = Get-Content -LiteralPath $status -Raw -Encoding utf8 | ConvertFrom-Json } catch { $doc = $null }
    }

    $verdict = 'awaiting-run'
    $phase = ''
    $vmState = ''
    $heartbeat = ''
    $stallLeft = 0
    $wallLeft = 0
    $lastHost = ''
    if ($null -ne $doc) {
        $age = 0
        try {
            $updated = [datetime]::Parse([string]$doc.updatedAt, $null, [Globalization.DateTimeStyles]::RoundtripKind)
            $age = [int]([datetime]::UtcNow - $updated.ToUniversalTime()).TotalSeconds
        }
        catch { $age = 0 }
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

    $logLeaf = ''
    $logTail = @()
    if ($log -and (Test-Path -LiteralPath $log)) {
        $logLeaf = Split-Path -Leaf $log
        $logTail = @(Get-Content -LiteralPath $log -Tail 8)
    }

    Clear-Host
    Write-Host (Format-WinMintHostWatch -Title $host.UI.RawUI.WindowTitle `
            -Clock (Get-Date -Format 'HH:mm:ss') -Verdict $verdict -Phase $phase `
            -VmState $vmState -Heartbeat $heartbeat -StallMinutesLeft $stallLeft `
            -WallMinutesLeft $wallLeft -ApplyStage $applyStage -LastHostLine $lastHost `
            -LogLeaf $logLeaf -LogTail $logTail)

    if ($verdict -eq 'done') {
        $doneTicks++
        if ($doneTicks -ge 3) { break }
    }
    else {
        $doneTicks = 0
    }
    Start-Sleep -Seconds 2
}
