#Requires -Version 7.3

<#
.SYNOPSIS
    WinMint UI logging, structured diagnostics, and shared error formatting.
.NOTES
    - Console: human-readable lines with ISO-local timestamps and correlation id.
    - Optional JSONL (%LocalAppData%\WinMint\logs\WinMint-UI-events.jsonl): one object per line for tooling.
    - Disable JSONL: set environment WINMINT_UI_NO_JSONL=1
#>

$script:WinMintUiLoggingInitialized = $false
$script:WinMintUiCorrelationId = $null
$script:WinMintUiLogJsonlDisabled = $false
$script:WinMintUiLogFileLock = [object]::new()
$script:WinMintUiProcessFaultHandlersRegistered = $false

function Get-WinMintUiLogDirectory {
    $d = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WinMint\logs'
    $null = New-Item -ItemType Directory -Path $d -Force -ErrorAction SilentlyContinue
    return $d
}

function Initialize-WinMintUiLogging {
    if ($script:WinMintUiLoggingInitialized) { return }
    $script:WinMintUiCorrelationId = [guid]::NewGuid().ToString('N')
    $script:WinMintUiLogJsonlDisabled = ($env:WINMINT_UI_NO_JSONL -eq '1')
    $script:WinMintUiLoggingInitialized = $true
    if ($script:WinMintUiLogJsonlDisabled) { return }
    try {
        $path = Join-Path (Get-WinMintUiLogDirectory) 'WinMint-UI-events.jsonl'
        $payload = @{
            ts          = (Get-Date).ToUniversalTime().ToString('o')
            level       = 'info'
            correlation = $script:WinMintUiCorrelationId
            pid         = $PID
            event       = 'session_start'
            pwsh        = $PSVersionTable.PSVersion.ToString()
            os          = [System.Environment]::OSVersion.VersionString
        }
        $line = ($payload | ConvertTo-Json -Compress -Depth 6)
        [System.Threading.Monitor]::Enter($script:WinMintUiLogFileLock)
        try {
            [System.IO.File]::AppendAllText($path, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        } finally {
            [System.Threading.Monitor]::Exit($script:WinMintUiLogFileLock)
        }
    } catch {}
}

function Get-WinMintUiCorrelationId {
    if (-not $script:WinMintUiLoggingInitialized) { Initialize-WinMintUiLogging }
    return $script:WinMintUiCorrelationId
}

function Format-WinMintUiErrorRecord {
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

function Write-WinMintUiJsonlEvent {
    param(
        [string]$Level,
        [string]$Message,
        [string]$Source
    )
    if ($script:WinMintUiLogJsonlDisabled) { return }
    try {
        if (-not $script:WinMintUiLoggingInitialized) { Initialize-WinMintUiLogging }
        $path = Join-Path (Get-WinMintUiLogDirectory) 'WinMint-UI-events.jsonl'
        $payload = @{
            ts          = (Get-Date).ToUniversalTime().ToString('o')
            level       = $Level.ToLowerInvariant()
            correlation = (Get-WinMintUiCorrelationId)
            pid         = $PID
            message     = $Message
        }
        if (-not [string]::IsNullOrWhiteSpace($Source)) { $payload.source = $Source }
        $line = ($payload | ConvertTo-Json -Compress -Depth 6)
        [System.Threading.Monitor]::Enter($script:WinMintUiLogFileLock)
        try {
            [System.IO.File]::AppendAllText($path, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        } finally {
            [System.Threading.Monitor]::Exit($script:WinMintUiLogFileLock)
        }
    } catch {}
}

function Write-WinMintUiLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,
        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'CRITICAL', 'OK')]
        [string]$Level = 'INFO',
        [string]$Source = ''
    )
    if (-not $script:WinMintUiLoggingInitialized) { Initialize-WinMintUiLogging }
    $norm = $Level
    if ($norm -eq 'OK') { $norm = 'INFO' }
    $stamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffK')
    $cid = (Get-WinMintUiCorrelationId)
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
    Write-WinMintUiJsonlEvent -Level $norm -Message $Message -Source $Source
}

function Export-WinMintUiFaultReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Body,
        [string]$RelativeFileName = 'WinMint-UI-last-crash.txt'
    )
    try {
        $dir = Get-WinMintUiLogDirectory
        $path = Join-Path $dir $RelativeFileName
        $header = "`n$(Get-Date -Format 'o') correlation=$(Get-WinMintUiCorrelationId) pid=$PID`n"
        [System.IO.File]::AppendAllText($path, $header + $Body + "`n", [System.Text.UTF8Encoding]::new($false))
    } catch {}
}

function Write-WinMintUiCrashDump {
    param([string]$Text)
    Export-WinMintUiFaultReport -Body $Text -RelativeFileName 'WinMint-UI-last-crash.txt'
}

function Register-WinMintUiProcessFaultHandlers {
    if ($script:WinMintUiProcessFaultHandlersRegistered) { return }
    $script:WinMintUiProcessFaultHandlersRegistered = $true
    try {
        [System.Threading.Tasks.TaskScheduler]::UnobservedTaskException += {
            param($taskSender, $taskEventArgs)
            [void]$taskSender
            try { $taskEventArgs.SetObserved() } catch {}
            try {
                $t = Format-WinMintUiErrorRecord -InputObject $taskEventArgs.Exception -AsSingleString
                Write-WinMintUiLog -Level WARN -Message "Unobserved task exception: $($taskEventArgs.Exception.Message)" -Source 'TaskScheduler'
                Export-WinMintUiFaultReport -Body $t -RelativeFileName 'WinMint-UI-unobserved-task.txt'
            } catch {}
        }
    } catch {}

    try {
        [AppDomain]::CurrentDomain.add_UnhandledException({
            param($domainSender, $domainArgs)
            [void]$domainSender
            try {
                $obj = $domainArgs.ExceptionObject
                $t = Format-WinMintUiErrorRecord -InputObject $obj -AsSingleString
                Write-WinMintUiLog -Level CRITICAL -Message "AppDomain unhandled (terminating=$($domainArgs.IsTerminating)): $($obj.Message)" -Source 'AppDomain'
                Export-WinMintUiFaultReport -Body $t -RelativeFileName 'WinMint-UI-appdomain-unhandled.txt'
            } catch {}
        })
    } catch {}
}

function Register-WinMintUiWpfDispatcherFaultHandling {
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
            $detail = Format-WinMintUiErrorRecord -InputObject $e.Exception -AsSingleString
        } catch {
            $detail = [string]$e.Exception
        }
        try {
            Export-WinMintUiFaultReport -Body $detail -RelativeFileName 'WinMint-UI-wpf-crash.txt'
        } catch {}
        Write-WinMintUiLog -Level CRITICAL -Message "Unhandled WPF dispatcher exception: $($e.Exception.Message)" -Source 'WPF.Dispatcher'
        Write-Host "`n--- Unhandled WPF exception ---`n$detail" -ForegroundColor Red
        $e.Handled = $true
        if (Get-Command Stop-WinMintUiSessionTranscript -ErrorAction SilentlyContinue) {
            Stop-WinMintUiSessionTranscript
        } else {
            try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
        }
        Read-Host 'Press Enter to exit (see %LOCALAPPDATA%\WinMint\logs\)'
        [Environment]::Exit(1)
    })
}
