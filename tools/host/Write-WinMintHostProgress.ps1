#requires -Version 7.6
# Host progress presentation ($PSStyle + Write-Progress). Not an opcode kernel.
# apply-status.txt / smoke-status.json stay the files.

Set-StrictMode -Version Latest

$script:WinMintHostProgressId = 7391
$script:WinMintHostProgressReady = $false

function Initialize-WinMintHostProgress {
    if ($script:WinMintHostProgressReady) { return }
    $script:WinMintHostProgressReady = $true
    try {
        $PSStyle.Progress.View = 'Minimal'
    }
    catch {
        Write-Debug "PSStyle.Progress.View: $_"
    }
}

function Write-WinMintHostPhase {
    param(
        [Parameter(Mandatory)] [string] $Lane,
        [Parameter(Mandatory)] [string] $Name,
        [int] $Index = 0,
        [int] $Count = 0,
        [string] $Outcome = '',
        [int] $DurationMs = -1
    )
    Initialize-WinMintHostProgress
    $bold = $PSStyle.Bold
    $reset = $PSStyle.Reset
    $accent = $PSStyle.Foreground.Cyan
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add("${bold}${accent}$Lane${reset}")
    if ($Count -gt 0 -and $Index -gt 0) {
        $parts.Add(('{0}/{1}' -f $Index, $Count))
    }
    $parts.Add($Name)
    if (-not [string]::IsNullOrWhiteSpace($Outcome)) {
        $color = if ($Outcome -eq 'ok') { $PSStyle.Foreground.Green } else { $PSStyle.Foreground.Red }
        $parts.Add("${color}$Outcome${reset}")
    }
    if ($DurationMs -ge 0) {
        $parts.Add(('{0:n1}s' -f ($DurationMs / 1000.0)))
    }
    Write-Host ($parts -join '  ')
}

function Write-WinMintHostProgress {
    param(
        [Parameter(Mandatory)] [string] $Activity,
        [string] $Status = '',
        [int] $PercentComplete = -1,
        [switch] $Completed
    )
    Initialize-WinMintHostProgress
    if ($Completed) {
        Write-Progress -Id $script:WinMintHostProgressId -Activity $Activity -Completed
        return
    }
    $progress = @{
        Id       = $script:WinMintHostProgressId
        Activity = $Activity
    }
    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        $progress.Status = $Status
    }
    if ($PercentComplete -ge 0) {
        $pct = [Math]::Min(100, [Math]::Max(0, $PercentComplete))
        $progress.PercentComplete = $pct
    }
    Write-Progress @progress
}

function Format-WinMintHostWatch {
    param(
        [string] $Title = '',
        [string] $Clock = '',
        [string] $Verdict = '',
        [string] $Phase = '',
        [string] $VmState = '',
        [string] $Heartbeat = '',
        [int] $StallMinutesLeft = 0,
        [int] $WallMinutesLeft = 0,
        [string] $ApplyStage = '',
        [string] $LastHostLine = '',
        [string] $LogLeaf = '',
        [string[]] $LogTail = @()
    )
    $bold = $PSStyle.Bold
    $reset = $PSStyle.Reset
    $lines = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Title)) {
        $lines.Add($Title)
    }
    if (-not [string]::IsNullOrWhiteSpace($Clock)) {
        $lines.Add($Clock)
    }
    $lines.Add('')
    $lines.Add("${bold}verdict${reset}  $Verdict")
    $lines.Add(('phase    {0,-14}  VM {1,-12}  heartbeat {2}' -f $Phase, $VmState, $Heartbeat))
    $lines.Add(('stall    {0}m             wall {1}m' -f $StallMinutesLeft, $WallMinutesLeft))
    $lines.Add("apply    $ApplyStage")
    if (-not [string]::IsNullOrWhiteSpace($LastHostLine)) {
        $lines.Add("host     $LastHostLine")
    }
    if (-not [string]::IsNullOrWhiteSpace($LogLeaf)) {
        $lines.Add('')
        $lines.Add("${bold}log${reset}      $LogLeaf")
        foreach ($row in @($LogTail | Select-Object -First 8)) {
            $lines.Add("  $row")
        }
    }
    return ($lines -join [Environment]::NewLine)
}
