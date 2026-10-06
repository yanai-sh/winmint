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
    param([Parameter(Mandatory)] [string] $Line)
    return [bool]($Line -match '^\S+ running \d+s$')
}

function Select-WinMintWatchLogTail {
    param(
        [string[]] $Lines = @(),
        [int] $Count = 8
    )
    $kept = @(
        $Lines |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not (Test-WinMintTrailHeartbeatLine -Line $_) }
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
                return [string]$failDoc.message
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
    if (-not [string]::IsNullOrWhiteSpace($Verdict)) {
        $lines.Add("${bold}verdict${reset}  $Verdict")
    }
    $showVm = $PSBoundParameters.ContainsKey('VmState') -or $PSBoundParameters.ContainsKey('Heartbeat') -or
        -not [string]::IsNullOrWhiteSpace($VmState) -or -not [string]::IsNullOrWhiteSpace($Heartbeat)
    if ($showVm) {
        $lines.Add(('phase    {0,-14}  VM {1,-12}  heartbeat {2}' -f $Phase, $VmState, $Heartbeat))
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Phase)) {
        $lines.Add("phase    $Phase")
    }
    if ($PSBoundParameters.ContainsKey('StallMinutesLeft') -or $PSBoundParameters.ContainsKey('WallMinutesLeft')) {
        $lines.Add(('stall    {0}m             wall {1}m' -f $StallMinutesLeft, $WallMinutesLeft))
    }
    if (-not [string]::IsNullOrWhiteSpace($ApplyStage)) {
        $lines.Add("apply    $ApplyStage")
    }
    if (-not [string]::IsNullOrWhiteSpace($Leaf)) {
        $lines.Add("leaf     $Leaf")
    }
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

function Resolve-WinMintWindowsTerminal {
    $cmd = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return [string]$cmd.Source }
    foreach ($candidate in @(
            (Join-Path $env:LocalAppData 'Microsoft\WindowsApps\wt.exe'),
            (Join-Path $env:ProgramFiles 'Windows Terminal\wt.exe')
        )) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return ''
}

function Start-WinMintHostWatchProcess {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $Work,
        [Parameter(Mandatory)] [ValidateSet('smoke', 'check', 'apply')] [string] $Kind,
        [string] $PriorRunId = '',
        [Parameter(Mandatory)] [string] $MarkerPath,
        [Parameter(Mandatory)] [string] $PwshExe
    )
    $watchScript = Join-Path $RepoRoot 'tools/host/Watch-Host.ps1'
    $title = "WinMint host watch — $Work"
    $pwshArgs = @(
        '-NoProfile', '-NonInteractive', '-File', $watchScript,
        '-Kind', $Kind, '-Work', $Work, '-MarkerPath', $MarkerPath
    )
    if ($PSBoundParameters.ContainsKey('PriorRunId')) {
        $pwshArgs += @('-PriorRunId', $PriorRunId)
    }
    $wt = Resolve-WinMintWindowsTerminal
    if ($wt) {
        $wtArgs = @(
            'new-tab',
            '--title', $title,
            '-d', $RepoRoot,
            '--',
            $PwshExe
        ) + $pwshArgs
        Start-Process -FilePath $wt -WorkingDirectory $RepoRoot -ArgumentList $wtArgs | Out-Null
        # ponytail: poll up to 5s for Watch self-stamp; Stopwatch (not UtcNow) — host clock can jump.
        $wait = [Diagnostics.Stopwatch]::StartNew()
        while ($wait.Elapsed.TotalSeconds -lt 5) {
            if (Test-Path -LiteralPath $MarkerPath -PathType Leaf) {
                $markerPid = 0
                $raw = (Get-Content -LiteralPath $MarkerPath -Raw -ErrorAction SilentlyContinue)
                if ($raw -and [int]::TryParse($raw.Trim(), [ref]$markerPid) -and $markerPid -gt 0) {
                    if ($null -ne (Get-Process -Id $markerPid -ErrorAction SilentlyContinue)) {
                        return
                    }
                }
            }
            Start-Sleep -Milliseconds 200
        }
        return
    }
    $proc = Start-Process -FilePath $PwshExe -WorkingDirectory $RepoRoot -PassThru -ArgumentList $pwshArgs
    Set-Content -LiteralPath $MarkerPath -Value $proc.Id -Encoding utf8
}
