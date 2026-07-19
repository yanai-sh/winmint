#Requires -Version 7.6
# Dot-sourced by WinMint-VmConsole.ps1 — not a standalone entrypoint.
$script:WinMintVmRunLogContext = @{
    LogPath = ''
    EventsPath = ''
    StartedAt = $null
    LastProgressSignature = ''
}

function Remove-WinMintVmAnsiEscape {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return [string]$Text }
    return [regex]::Replace($Text, "\e\[[\d;?]*[ -/]*[@-~]", '')
}

function Format-WinMintVmLogTimestamp {
    param([datetime]$When = (Get-Date))
    return $When.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
}

function Format-WinMintVmDuration {
    param([TimeSpan]$Span)

    if ($Span -lt [TimeSpan]::Zero) { $Span = [TimeSpan]::Zero }
    $totalMinutes = [int][math]::Floor($Span.TotalMinutes)
    $seconds = $Span.Seconds
    if ($totalMinutes -ge 60) {
        $hours = [int][math]::Floor($totalMinutes / 60)
        $minutes = $totalMinutes % 60
        return ('{0}h {1:D2}m' -f $hours, $minutes)
    }
    return ('{0}:{1:D2}' -f $totalMinutes, $seconds)
}

function Format-WinMintVmLogRecord {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'PHASE', 'PROG', 'SUB', 'WARN', 'ERROR', 'DONE', 'META')]
        [string]$Level = 'INFO',
        [datetime]$When = (Get-Date)
    )

    $body = Remove-WinMintVmAnsiEscape $Message
    $stamp = Format-WinMintVmLogTimestamp -When $When
    return "[$stamp] [$($Level.PadRight(5))] $body"
}

function Set-WinMintVmRunLogContext {
    param(
        [string]$LogPath,
        [string]$EventsPath,
        [Nullable[datetime]]$StartedAt
    )

    if ($LogPath) { $script:WinMintVmRunLogContext.LogPath = $LogPath }
    if ($EventsPath) { $script:WinMintVmRunLogContext.EventsPath = $EventsPath }
    if ($StartedAt) { $script:WinMintVmRunLogContext.StartedAt = $StartedAt }
}

function Initialize-WinMintVmRunLog {
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][hashtable]$Meta
    )

    $eventsPath = Join-Path (Split-Path -Parent $LogPath) 'run-events.jsonl'
    $startedAt = if ($Meta.startedAt) { [datetime]$Meta.startedAt } else { Get-Date }
    Set-WinMintVmRunLogContext -LogPath $LogPath -EventsPath $eventsPath -StartedAt $startedAt
    $script:WinMintVmRunLogContext.LastProgressSignature = ''

    $banner = @(
        '================================================================================'
        ' WinMint VM Acceptance Run Log'
        '================================================================================'
    )
    foreach ($line in $banner) {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    }
    foreach ($entry in ($Meta.GetEnumerator() | Sort-Object { [string]$_.Key })) {
        $record = Format-WinMintVmLogRecord -Message ("{0}={1}" -f $entry.Key, $entry.Value) -Level 'META' -When $startedAt
        Add-Content -LiteralPath $LogPath -Value $record -Encoding UTF8
    }
    Add-Content -LiteralPath $LogPath -Value ($banner[0]) -Encoding UTF8

    Write-WinMintVmRunEvent -Kind 'run-start' -Payload $Meta
    return $eventsPath
}

function Write-WinMintVmRunEvent {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [hashtable]$Payload = @{}
    )

    $eventsPath = [string]$script:WinMintVmRunLogContext.EventsPath
    if (-not $eventsPath) { return }

    $event = [ordered]@{ t = (Format-WinMintVmLogTimestamp); kind = $Kind }
    foreach ($entry in $Payload.GetEnumerator()) {
        $event[$entry.Key] = $entry.Value
    }
    Add-Content -LiteralPath $eventsPath -Value ($event | ConvertTo-Json -Compress) -Encoding UTF8
}

function Write-WinMintVmProgressEvent {
    param(
        [Parameter(Mandatory)][hashtable]$Snapshot
    )

    $signature = ($Snapshot.GetEnumerator() | Sort-Object Key | ForEach-Object { "{0}={1}" -f $_.Key, $_.Value }) -join '|'
    if ($signature -eq $script:WinMintVmRunLogContext.LastProgressSignature) { return }
    $script:WinMintVmRunLogContext.LastProgressSignature = $signature
    Write-WinMintVmRunEvent -Kind 'progress' -Payload $Snapshot
}

function Resolve-WinMintVmLogLevel {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Color,
        [switch]$Subprocess
    )

    if ($Subprocess) { return 'SUB' }
    $plain = Remove-WinMintVmAnsiEscape $Message
    if ($plain -match '^\s*===\s*.+\s*===') { return 'PHASE' }
    if ($plain -match '^\s*\[.*elapsed.*left\]') { return 'PROG' }
    if ($Color -eq 'Red' -or $plain -match '(?i)^(Build failed|Inspect failed|FirstLogon failed|fatal error|Exception:)') { return 'ERROR' }
    if ($Color -eq 'Yellow' -or $plain -match '(?i)^WARNING:|Time budget exceeded') { return 'WARN' }
    if ($Color -eq 'Green' -or $plain -match '(?i)^=== Overall verdict:|^FirstLogon completed') { return 'DONE' }
    return 'INFO'
}

function Write-WinMintVmLogLine {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$LogPath,
        [string]$Color,
        [ValidateSet('INFO', 'PHASE', 'PROG', 'SUB', 'WARN', 'ERROR', 'DONE', 'META', 'Auto')]
        [string]$Level = 'Auto',
        [switch]$Subprocess
    )

    if (-not $LogPath) { $LogPath = [string]$script:WinMintVmRunLogContext.LogPath }
    $resolvedLevel = if ($Level -eq 'Auto') { Resolve-WinMintVmLogLevel -Message $Message -Color $Color -Subprocess:$Subprocess } else { $Level }
    $consoleText = Remove-WinMintVmAnsiEscape $Message
    $fileLine = Format-WinMintVmLogRecord -Message $Message -Level $resolvedLevel

    if ($Color) { Write-Host $consoleText -ForegroundColor $Color }
    else { Write-Host $consoleText }
    if ($LogPath) { Add-Content -LiteralPath $LogPath -Value $fileLine -Encoding UTF8 }
    try { [Console]::Out.Flush() } catch {}

    if ($resolvedLevel -eq 'PHASE') {
        $phaseName = ($consoleText -replace '^\s*===\s*', '' -replace '\s*===\s*$', '').Trim()
        if ($phaseName) { Write-WinMintVmRunEvent -Kind 'phase' -Payload @{ phase = $phaseName } }
    }
}

function ConvertTo-WinMintVmLogText {
    param([Parameter(ValueFromPipeline = $true)]$Record)

    process {
        switch ($Record) {
            { $_ -is [System.Management.Automation.ErrorRecord] } { return $_.ToString() }
            { $_ -is [System.Management.Automation.WarningRecord] } { return $_.Message }
            { $_ -is [System.Management.Automation.VerboseRecord] } { return $_.Message }
            { $_ -is [System.Management.Automation.DebugRecord] } { return $_.Message }
            { $_ -is [System.Management.Automation.InformationRecord] } { return $_.ToString() }
            default { return [string]$_ }
        }
    }
}

function Invoke-WinMintVmLoggedCommand {
    [CmdletBinding(DefaultParameterSetName = 'Native')]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(ParameterSetName = 'ScriptBlock', Mandatory)][scriptblock]$Command,
        [Parameter(ParameterSetName = 'Native', Mandatory)][string]$FilePath,
        [Parameter(ParameterSetName = 'Native')][string[]]$ArgumentList = @()
    )

    $emit = {
        param([string]$Text)
        if ([string]::IsNullOrWhiteSpace($Text)) { return }
        Write-WinMintVmLogLine -Message $Text -LogPath $LogPath -Subprocess -Level 'SUB'
    }

    if ($PSCmdlet.ParameterSetName -eq 'ScriptBlock') {
        & $Command 6>&1 | ForEach-Object { & $emit ((ConvertTo-WinMintVmLogText $_)) }
    }
    else {
        & $FilePath @ArgumentList 6>&1 | ForEach-Object { & $emit ((ConvertTo-WinMintVmLogText $_)) }
    }
    if ($null -ne $LASTEXITCODE) { return [int]$LASTEXITCODE }
    return 0
}

function Get-WinMintVmBuildVerboseLogPath {
    param([Parameter(Mandatory)][string]$RepoRoot)
    return (Join-Path $RepoRoot 'output\WinMint-Build.verbose.log')
}

function Invoke-WinMintVmSpectreBuildCommand {
    <#
    .SYNOPSIS
        Run the ISO build/boot child with dual-channel engine logging (777a722).

    .DESCRIPTION
        Does NOT pipe stdout through [SUB] — that strips PwshSpectreConsole progress
        and duplicates the verbose file. Human Spectre stays on the inherited
        console; full detail always lands in output\WinMint-Build.verbose.log.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    $verboseLog = Get-WinMintVmBuildVerboseLogPath -RepoRoot $RepoRoot
    Write-WinMintVmLogLine -Message "Build uses dual-channel Spectre console + verbose log: $verboseLog" -LogPath $LogPath -Level 'META'
    Write-WinMintVmLogLine -Message 'Tail verbose: Get-Content -LiteralPath .\output\WinMint-Build.verbose.log -Wait -Tail 40' -LogPath $LogPath -Level 'META'
    Write-WinMintVmRunEvent -Kind 'milestone' -Payload @{ label = 'build-spectre-channels'; verboseLog = $verboseLog }

    # Start-Process keeps Spectre on the inherited console and returns only ExitCode.
    # A bare `& $FilePath` also streams success output into this function's return value,
    # so callers saw a giant string as $buildExit and false-failed after exit 0.
    $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $RepoRoot `
        -Wait -PassThru -NoNewWindow
    $code = if ($null -ne $proc.ExitCode) { [int]$proc.ExitCode } else { 0 }
    Write-WinMintVmLogLine -Message "Build/boot child exited $code (detail: $verboseLog)" -LogPath $LogPath -Level $(if ($code -eq 0) { 'DONE' } else { 'ERROR' })
    return $code
}

function Get-WinMintVmRunEventsTail {
    param(
        [string]$EventsPath,
        [int]$Tail = 8
    )

    if (-not $EventsPath -or -not (Test-Path -LiteralPath $EventsPath)) { return @() }
    $lines = @(Get-Content -LiteralPath $EventsPath -Tail $Tail -ErrorAction SilentlyContinue)
    $events = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $events.Add(($line | ConvertFrom-Json)) | Out-Null } catch { }
    }
    return @($events)
}

function Get-WinMintVmRunProgressFromEvents {
    param([string]$EventsPath)

    $progress = [ordered]@{
        phase = ''
        phaseStartedAt = ''
        vmState = ''
        guestRunStatus = ''
        setupShellPhase = ''
        currentStep = ''
        stepsCompleted = $null
        stepsTotal = $null
        lastProgressAt = ''
        milestones = @()
    }
    if (-not $EventsPath -or -not (Test-Path -LiteralPath $EventsPath)) { return $progress }

    $milestones = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @(Get-Content -LiteralPath $EventsPath -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $event = $line | ConvertFrom-Json } catch { continue }
        $kind = [string]$event.kind
        if ($kind -eq 'phase') {
            $progress.phase = [string]$event.phase
            $progress.phaseStartedAt = [string]$event.t
        }
        elseif ($kind -eq 'milestone') {
            $label = [string]$event.label
            if ($label) { $milestones.Add($label) | Out-Null }
        }
        elseif ($kind -eq 'progress') {
            foreach ($name in @('vmState', 'guestRunStatus', 'setupShellPhase', 'currentStep', 'stepsCompleted', 'stepsTotal', 'guestPollMs', 'guestPollTimedOut')) {
                if ($event.PSObject.Properties[$name]) { $progress[$name] = $event.$name }
            }
            $progress.lastProgressAt = [string]$event.t
        }
        elseif ($kind -eq 'build-plan') {
            if ($event.PSObject.Properties['strategy']) { $progress.buildStrategy = [string]$event.strategy }
            if ($event.PSObject.Properties['estimatedMinutes']) { $progress.buildEstimatedMinutes = [string]$event.estimatedMinutes }
        }
        elseif ($kind -eq 'verdict') {
            $milestones.Add("verdict=$($event.verdict)") | Out-Null
        }
    }
    $progress.milestones = @($milestones)
    return $progress
}

function Get-WinMintVmInferredRunPhase {
    param(
        [string[]]$Tail,
        [string]$StoredPhase
    )

    $text = ($Tail -join "`n")
    if ($text -match '(?i)=== Wait for FirstLogon ===') { return 'Wait for FirstLogon' }
    if ($text -match '(?i)=== Inspect ===') { return 'Inspect' }
    if ($text -match '(?i)=== Evidence ===') { return 'Evidence' }
    if ($text -match '(?i)Push-only iteration') { return 'Push-only' }
    if ($text -match '(?i)first-logon breadcrumb|waiting for first-logon breadcrumb') { return 'BuildBoot-breadcrumb' }
    if ($text -match '(?i)Creating .+ from .+\.iso|Started .+: \d+ GB RAM') { return 'BuildBoot-install' }
    if ($text -match '(?i)Offline WIM removal') { return 'BuildBoot-offline-verify' }
    if ($text -match '(?i)Reusing PostSetup checkpoint|checkpoint-push-complete') { return 'BuildBoot-checkpoint' }
    if ($text -match '(?i)Building ISO from profile|Service WIM|Invoking ISO pipeline|reusing existing ISO') { return 'BuildBoot-build' }
    if ($text -match '(?i)=== Build ===') { return 'Build' }

    if ($StoredPhase -and $StoredPhase -notin @('starting', 'init', '')) {
        return $StoredPhase
    }
    return $StoredPhase
}

function Get-WinMintVmRunLogFreshnessMinutes {
    param([string]$RunLog)

    if (-not $RunLog -or -not (Test-Path -LiteralPath $RunLog)) { return $null }
    try {
        $lastWrite = (Get-Item -LiteralPath $RunLog).LastWriteTime
        return [math]::Round(((Get-Date) - $lastWrite).TotalMinutes, 1)
    }
    catch { return $null }
}

function Get-WinMintVmSignificantLogTail {
    param(
        [string]$RunLog,
        [int]$Tail = 20,
        [int]$Scan = 120
    )

    if (-not $RunLog -or -not (Test-Path -LiteralPath $RunLog)) { return @() }
    $lines = @(Get-Content -LiteralPath $RunLog -Tail $Scan -ErrorAction SilentlyContinue)
    $filtered = @($lines | Where-Object {
            $_ -notmatch '\] \[PROG \]' -and $_ -notmatch '\] \[PROG\]'
        })
    if ($filtered.Count -gt $Tail) { return @($filtered[-$Tail..-1]) }
    return @($filtered)
}

function Test-WinMintVmLogSanitizer {
    $dirty = "`e[33;1mWARNING: test`e[0m"
    $clean = Remove-WinMintVmAnsiEscape $dirty
    if ($clean -ne 'WARNING: test') { throw 'Remove-WinMintVmAnsiEscape failed.' }
    return $true
}
