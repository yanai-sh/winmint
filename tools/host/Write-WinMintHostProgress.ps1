#requires -Version 7.6
# Host progress presentation ($PSStyle + Write-Progress). Not an opcode kernel.
# apply-status.txt / smoke-status.json stay the files.

Set-StrictMode -Version Latest

$script:WinMintHostProgressId = 7391
$script:WinMintHostProgressReady = $false

function Test-WinMintHostProgressInteractive {
    try {
        return -not [Console]::IsOutputRedirected -and $Host.UI.SupportsVirtualTerminal
    }
    catch {
        return $false
    }
}

function Initialize-WinMintHostProgress {
    if ($script:WinMintHostProgressReady) { return }
    $script:WinMintHostProgressReady = $true
    try {
        $PSStyle.Progress.View = 'Minimal'
        if (Test-WinMintHostProgressInteractive) {
            $PSStyle.Progress.UseOSCIndicator = $true
        }
    }
    catch {
        Write-Debug "PSStyle.Progress: $_"
    }
}

function Test-WinMintTrailHeartbeatLine {
    # Allow empty: kernel tee can emit blank lines; Mandatory+ValidateNotNullOrEmpty would throw.
    param([string] $Line = '')
    if ([string]::IsNullOrEmpty($Line)) { return $false }
    return [bool]($Line -match '^\S+ running \d+s$')
}

function Test-WinMintDismProgressBarLine {
    # Allow empty: kernel tee can emit blank lines; Mandatory+ValidateNotNullOrEmpty would throw.
    param([string] $Line = '')
    if ([string]::IsNullOrEmpty($Line)) { return $false }
    return [bool]($Line -match '^\s*\[.*\d+\.\d+%\s*\]')
}

function Select-WinMintWatchLogTail {
    param(
        [string[]] $Lines = @(),
        [int] $Count = 8
    )
    $kept = @(
        $Lines |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                -not (Test-WinMintTrailHeartbeatLine -Line $_) -and
                -not (Test-WinMintDismProgressBarLine -Line $_)
            }
    )
    if ($kept.Count -le $Count) { return $kept }
    return @($kept | Select-Object -Last $Count)
}

function Write-WinMintHostHeartbeat {
    param(
        [Parameter(Mandatory)] [string] $Opcode,
        [Parameter(Mandatory)] [int] $ElapsedSeconds,
        [IO.TextWriter] $LogWriter = $null,
        [string] $Activity = 'Apply'
    )
    Initialize-WinMintHostProgress
    $text = "$Opcode running ${ElapsedSeconds}s"
    if ($null -ne $LogWriter) {
        $LogWriter.WriteLine($text)
    }
    Write-WinMintHostProgress -Activity $Activity -Status $text
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

function Read-WinMintApplyStatus {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    $stage = ''
    $log = ''
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line.StartsWith('stage=')) { $stage = $line.Substring(6) }
        elseif ($line.StartsWith('log=')) { $log = $line.Substring(4) }
    }
    [pscustomobject]@{ Stage = $stage; Log = $log }
}

function Format-WinMintServicingLockFailure {
    param([string] $Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { return $null }
    if ($Message -notmatch '(?i)servicing already active') { return $null }
    return 'servicing already active — another Apply holds the ImageServicing lock; wait or just discard-stale-mount'
}

function Get-WinMintWatchConsoleWidth {
    try {
        $w = [Console]::WindowWidth
        if ($w -ge 40) { return [int]$w }
    }
    catch {
        Write-Debug "console width: $_"
    }
    return 100
}

function Format-WinMintWatchClip {
    param(
        [AllowEmptyString()]
        [string] $Text = '',
        [int] $MaxWidth = 0
    )
    # Clip (don’t mid-word wrap): long PackageName lines destroyed Watch readability.
    if ($MaxWidth -le 0) { $MaxWidth = Get-WinMintWatchConsoleWidth }
    if ($MaxWidth -lt 8) { return $Text }
    $plain = $Text -replace '\x1b\[[0-9;]*m', ''
    if ($plain.Length -le $MaxWidth) { return $Text }
    return ($plain.Substring(0, $MaxWidth - 1) + '…')
}

function Get-WinMintApplyHostFailure {
    param([Parameter(Mandatory)] [string] $WorkDirectory)
    $applyStatusPath = Join-Path $WorkDirectory 'apply-status.txt'
    if (-not (Test-Path -LiteralPath $applyStatusPath -PathType Leaf)) {
        return $null
    }
    $applyStatus = Get-Content -LiteralPath $applyStatusPath -Raw -Encoding utf8
    if ($applyStatus -notmatch 'stage=failed:') {
        return $null
    }
    $failureJson = Join-Path $WorkDirectory 'failure.json'
    if (Test-Path -LiteralPath $failureJson -PathType Leaf) {
        try {
            $failDoc = Get-Content -LiteralPath $failureJson -Raw -Encoding utf8 | ConvertFrom-Json
            if (-not [string]::IsNullOrWhiteSpace([string]$failDoc.message)) {
                $msg = [string]$failDoc.message
                $lock = Format-WinMintServicingLockFailure -Message $msg
                return $(if ($lock) { $lock } else { $msg })
            }
        }
        catch {
            Write-Verbose "failure.json unreadable: $($_.Exception.Message)"
        }
    }
    return 'Apply failed (apply-status)'
}

function Format-WinMintHostWatch {
    param(
        [string] $Title = '',
        [string] $Clock = '',
        [string] $Verdict = '',
        [string] $Phase = '',
        [string] $Leaf = '',
        [string] $VmState = '',
        [string] $Heartbeat = '',
        [int] $StallMinutesLeft = 0,
        [int] $WallMinutesLeft = 0,
        [string] $ApplyStage = '',
        [string] $LastHostLine = '',
        [string] $LogLeaf = '',
        [string[]] $LogTail = @()
    )
    # ponytail: ANSI via $PSStyle only (WT); PlainText / NO_COLOR strips for contracts & agents.
    $bold = $PSStyle.Bold
    $dim = $PSStyle.Foreground.BrightBlack
    $reset = $PSStyle.Reset
    # Width 10 so "heartbeat" keeps a trailing gap before the value.
    $lbl = { param([string] $Name) "${dim}$($Name.PadRight(10))$reset" }
    $verdictColor = switch -Regex ($Verdict) {
        '^(done|green)$' { $PSStyle.Foreground.Green; break }
        '^(failed|fail)$' { $PSStyle.Foreground.Red; break }
        '^awaiting' { $PSStyle.Foreground.Yellow; break }
        '^continue$' { $PSStyle.Foreground.Cyan; break }
        default { $PSStyle.Foreground.White }
    }
    $phaseColor = switch -Regex ($Phase) {
        '^(done|green)$' { $PSStyle.Foreground.Green; break }
        '^(failed|fail)$' { $PSStyle.Foreground.Red; break }
        '^(apply|wait|boot)' { $PSStyle.Foreground.Cyan; break }
        default { $PSStyle.Foreground.White }
    }
    $applyColor = if ($ApplyStage -match '^failed') { $PSStyle.Foreground.Red }
        elseif ($ApplyStage -eq 'done') { $PSStyle.Foreground.Green }
        else { $PSStyle.Foreground.Cyan }
    $empty = "${dim}-${reset}"
    $lines = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Title)) {
        $lines.Add("${bold}${Title}${reset}")
    }
    if (-not [string]::IsNullOrWhiteSpace($Clock)) {
        $lines.Add("${dim}${Clock}${reset}")
    }
    $lines.Add('')
    if (-not [string]::IsNullOrWhiteSpace($Verdict)) {
        $lines.Add(("$( & $lbl 'verdict' )${verdictColor}${Verdict}${reset}"))
    }
    $showVm = $PSBoundParameters.ContainsKey('VmState') -or $PSBoundParameters.ContainsKey('Heartbeat') -or
        -not [string]::IsNullOrWhiteSpace($VmState) -or -not [string]::IsNullOrWhiteSpace($Heartbeat)
    if ($showVm) {
        $phaseText = if ([string]::IsNullOrWhiteSpace($Phase)) { $empty } else { "${phaseColor}${Phase}${reset}" }
        $vmText = if ([string]::IsNullOrWhiteSpace($VmState)) { $empty } else { $VmState }
        $hbText = if ([string]::IsNullOrWhiteSpace($Heartbeat)) { $empty } else { $Heartbeat }
        $lines.Add(("$( & $lbl 'phase' )${phaseText}"))
        $lines.Add(("$( & $lbl 'vm' )${vmText}"))
        $lines.Add(("$( & $lbl 'heartbeat' )${hbText}"))
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Phase)) {
        $lines.Add(("$( & $lbl 'phase' )${phaseColor}${Phase}${reset}"))
    }
    if ($PSBoundParameters.ContainsKey('StallMinutesLeft') -or $PSBoundParameters.ContainsKey('WallMinutesLeft')) {
        $lines.Add(("$( & $lbl 'stall' ){0}m  ${dim}wall${reset} {1}m" -f $StallMinutesLeft, $WallMinutesLeft))
    }
    if (-not [string]::IsNullOrWhiteSpace($ApplyStage) -or
        -not [string]::IsNullOrWhiteSpace($Leaf) -or
        -not [string]::IsNullOrWhiteSpace($LastHostLine)) {
        $lines.Add('')
    }
    if (-not [string]::IsNullOrWhiteSpace($ApplyStage)) {
        $lines.Add(("$( & $lbl 'apply' )${applyColor}${ApplyStage}${reset}"))
    }
    if (-not [string]::IsNullOrWhiteSpace($Leaf)) {
        $lines.Add(("$( & $lbl 'leaf' )${Leaf}"))
    }
    $width = Get-WinMintWatchConsoleWidth
    # Label block is 10 chars + gap; log rows use "  │ " (4 visible).
    $valueWidth = [Math]::Max(24, $width - 12)
    $logWidth = [Math]::Max(24, $width - 4)
    if (-not [string]::IsNullOrWhiteSpace($LastHostLine)) {
        $hostClip = Format-WinMintWatchClip -Text $LastHostLine -MaxWidth $valueWidth
        $lines.Add(("$( & $lbl 'host' )${hostClip}"))
    }
    if (-not [string]::IsNullOrWhiteSpace($LogLeaf)) {
        $lines.Add('')
        $lines.Add(("$( & $lbl 'log' )${bold}${LogLeaf}${reset}"))
        foreach ($row in @($LogTail | Select-Object -First 8)) {
            $clip = Format-WinMintWatchClip -Text $row -MaxWidth $logWidth
            $lines.Add("  ${dim}│${reset} $clip")
        }
    }
    return ($lines -join [Environment]::NewLine)
}

. (Join-Path $PSScriptRoot 'WinMintHostConsole.ps1')
