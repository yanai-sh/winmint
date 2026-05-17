#Requires -Version 7.3

<#
.SYNOPSIS
    WinWS UI logging, structured diagnostics, and shared error formatting.
.NOTES
    - Console: human-readable lines with ISO-local timestamps and correlation id.
    - Optional JSONL (%LocalAppData%\WinWS\logs\WinMint-UI-events.jsonl): one object per line for tooling.
    - Disable JSONL: set environment WINWS_UI_NO_JSONL=1
#>

$script:WinWSUiLoggingInitialized = $false
$script:WinWSUiCorrelationId = $null
$script:WinWSUiLogJsonlDisabled = $false
$script:WinWSUiLogFileLock = [object]::new()
$script:WinWSUiProcessFaultHandlersRegistered = $false

function Get-WinWSUiLogDirectory {
    $d = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WinWS\logs'
    $null = New-Item -ItemType Directory -Path $d -Force -ErrorAction SilentlyContinue
    return $d
}

function Initialize-WinWSUiLogging {
    if ($script:WinWSUiLoggingInitialized) { return }
    $script:WinWSUiCorrelationId = [guid]::NewGuid().ToString('N')
    $script:WinWSUiLogJsonlDisabled = ($env:WINWS_UI_NO_JSONL -eq '1')
    $script:WinWSUiLoggingInitialized = $true
    if ($script:WinWSUiLogJsonlDisabled) { return }
    try {
        $path = Join-Path (Get-WinWSUiLogDirectory) 'WinMint-UI-events.jsonl'
        $payload = @{
            ts          = (Get-Date).ToUniversalTime().ToString('o')
            level       = 'info'
            correlation = $script:WinWSUiCorrelationId
            pid         = $PID
            event       = 'session_start'
            pwsh        = $PSVersionTable.PSVersion.ToString()
            os          = [System.Environment]::OSVersion.VersionString
        }
        $line = ($payload | ConvertTo-Json -Compress -Depth 6)
        [System.Threading.Monitor]::Enter($script:WinWSUiLogFileLock)
        try {
            [System.IO.File]::AppendAllText($path, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        } finally {
            [System.Threading.Monitor]::Exit($script:WinWSUiLogFileLock)
        }
    } catch {}
}

function Get-WinWSUiCorrelationId {
    if (-not $script:WinWSUiLoggingInitialized) { Initialize-WinWSUiLogging }
    return $script:WinWSUiCorrelationId
}

function Format-WinWSUiErrorRecord {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        $InputObject,
        [switch]$AsSingleString
    )
    process {
        $sb = [System.Text.StringBuilder]::new()
        if ($InputObject -is [System.Management.Automation.ErrorRecord]) {
            $er = $InputObject
            [void]$sb.AppendLine($er.ToString())
            if ($er.CategoryInfo) {
                [void]$sb.AppendLine(('Category   : {0}' -f $er.CategoryInfo))
            }
            if ($er.FullyQualifiedErrorId) {
                [void]$sb.AppendLine(('FqErrorId  : {0}' -f $er.FullyQualifiedErrorId))
            }
            if ($er.InvocationInfo -and $er.InvocationInfo.PositionMessage) {
                [void]$sb.AppendLine($er.InvocationInfo.PositionMessage.TrimEnd())
            }
            if ($er.ScriptStackTrace) {
                [void]$sb.AppendLine('ScriptStackTrace:')
                [void]$sb.AppendLine($er.ScriptStackTrace.TrimEnd())
            }
            if ($er.Exception -and $er.Exception.StackTrace) {
                [void]$sb.AppendLine('Exception.StackTrace:')
                [void]$sb.AppendLine($er.Exception.StackTrace.TrimEnd())
            }
            if ($er.Exception) {
                $inner = $er.Exception.InnerException
                $d = 0
                while ($null -ne $inner -and $d -lt 8) {
                    [void]$sb.AppendLine(('InnerException: {0}: {1}' -f $inner.GetType().FullName, $inner.Message))
                    $inner = $inner.InnerException
                    $d++
                }
            }
        } elseif ($InputObject -is [Exception]) {
            $w = $InputObject
            $depth = 0
            while ($null -ne $w -and $depth -lt 12) {
                [void]$sb.AppendLine(('--- {0}: {1}' -f $w.GetType().FullName, $w.Message))
                if ($w.StackTrace) {
                    [void]$sb.AppendLine($w.StackTrace.TrimEnd())
                }
                $w = $w.InnerException
                $depth++
            }
        } else {
            [void]$sb.AppendLine([string]$InputObject)
        }
        $text = $sb.ToString().TrimEnd()
        if ($AsSingleString) { return $text }
        return $text
    }
}

function Write-WinWSUiJsonlEvent {
    param(
        [string]$Level,
        [string]$Message,
        [string]$Source
    )
    if ($script:WinWSUiLogJsonlDisabled) { return }
    try {
        if (-not $script:WinWSUiLoggingInitialized) { Initialize-WinWSUiLogging }
        $path = Join-Path (Get-WinWSUiLogDirectory) 'WinMint-UI-events.jsonl'
        $payload = @{
            ts          = (Get-Date).ToUniversalTime().ToString('o')
            level       = $Level.ToLowerInvariant()
            correlation = (Get-WinWSUiCorrelationId)
            pid         = $PID
            message     = $Message
        }
        if (-not [string]::IsNullOrWhiteSpace($Source)) { $payload.source = $Source }
        $line = ($payload | ConvertTo-Json -Compress -Depth 6)
        [System.Threading.Monitor]::Enter($script:WinWSUiLogFileLock)
        try {
            [System.IO.File]::AppendAllText($path, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        } finally {
            [System.Threading.Monitor]::Exit($script:WinWSUiLogFileLock)
        }
    } catch {}
}

function Write-WinWSUiLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,
        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'CRITICAL', 'OK')]
        [string]$Level = 'INFO',
        [string]$Source = ''
    )
    if (-not $script:WinWSUiLoggingInitialized) { Initialize-WinWSUiLogging }
    $norm = $Level
    if ($norm -eq 'OK') { $norm = 'INFO' }
    $stamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffK')
    $cid = (Get-WinWSUiCorrelationId)
    $src = if ([string]::IsNullOrWhiteSpace($Source)) { '' } else { " [$Source]" }
    $line = "[$stamp] [$norm]$src [$cid] $Message"
    $color = switch ($norm) {
        'TRACE' { 'DarkGray' }
        'DEBUG' { 'Gray' }
        'INFO' { 'White' }
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
        'CRITICAL' { 'Magenta' }
        default { 'White' }
    }
    Write-Host $line -ForegroundColor $color
    Write-WinWSUiJsonlEvent -Level $norm -Message $Message -Source $Source
}

function Export-WinWSUiFaultReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Body,
        [string]$RelativeFileName = 'WinMint-UI-last-crash.txt'
    )
    try {
        $dir = Get-WinWSUiLogDirectory
        $path = Join-Path $dir $RelativeFileName
        $header = "`n$(Get-Date -Format 'o') correlation=$(Get-WinWSUiCorrelationId) pid=$PID`n"
        [System.IO.File]::AppendAllText($path, $header + $Body + "`n", [System.Text.UTF8Encoding]::new($false))
    } catch {}
}

function Write-WinWSUiCrashDump {
    param([string]$Text)
    Export-WinWSUiFaultReport -Body $Text -RelativeFileName 'WinMint-UI-last-crash.txt'
}

function Register-WinWSUiProcessFaultHandlers {
    if ($script:WinWSUiProcessFaultHandlersRegistered) { return }
    $script:WinWSUiProcessFaultHandlersRegistered = $true
    try {
        [System.Threading.Tasks.TaskScheduler]::UnobservedTaskException += {
            param($taskSender, $taskEventArgs)
            [void]$taskSender
            try { $taskEventArgs.SetObserved() } catch {}
            try {
                $t = Format-WinWSUiErrorRecord -InputObject $taskEventArgs.Exception -AsSingleString
                Write-WinWSUiLog -Level WARN -Message "Unobserved task exception: $($taskEventArgs.Exception.Message)" -Source 'TaskScheduler'
                Export-WinWSUiFaultReport -Body $t -RelativeFileName 'WinMint-UI-unobserved-task.txt'
            } catch {}
        }
    } catch {}

    try {
        [AppDomain]::CurrentDomain.add_UnhandledException({
            param($domainSender, $domainArgs)
            [void]$domainSender
            try {
                $obj = $domainArgs.ExceptionObject
                $t = Format-WinWSUiErrorRecord -InputObject $obj -AsSingleString
                Write-WinWSUiLog -Level CRITICAL -Message "AppDomain unhandled (terminating=$($domainArgs.IsTerminating)): $($obj.Message)" -Source 'AppDomain'
                Export-WinWSUiFaultReport -Body $t -RelativeFileName 'WinMint-UI-appdomain-unhandled.txt'
            } catch {}
        })
    } catch {}
}

function Register-WinWSUiWpfDispatcherFaultHandling {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Threading.Dispatcher]$Dispatcher
    )
    $null = $Dispatcher.add_UnhandledException({
        param($dispatcherSender, $e)
        [void]$dispatcherSender
        $detail = $null
        try {
            $detail = Format-WinWSUiErrorRecord -InputObject $e.Exception -AsSingleString
        } catch {
            $detail = [string]$e.Exception
        }
        try {
            Export-WinWSUiFaultReport -Body $detail -RelativeFileName 'WinMint-UI-wpf-crash.txt'
        } catch {}
        Write-WinWSUiLog -Level CRITICAL -Message "Unhandled WPF dispatcher exception: $($e.Exception.Message)" -Source 'WPF.Dispatcher'
        Write-Host "`n--- Unhandled WPF exception ---`n$detail" -ForegroundColor Red
        $e.Handled = $true
        if (Get-Command Stop-WinWSUiSessionTranscript -ErrorAction SilentlyContinue) {
            Stop-WinWSUiSessionTranscript
        } else {
            try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
        }
        Read-Host 'Press Enter to exit (see %LOCALAPPDATA%\WinWS\logs\)'
        [Environment]::Exit(1)
    })
}
