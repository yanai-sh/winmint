#Requires -Version 7.6

function Sync-Win11IsoSpectreConsoleDimension {
    <#
    <summary>
    Sets Spectre.Console profile width/height to the visible host window.
    Falls back to an assumed Windows Terminal viewport when RawUI is missing.
    </summary>
    #>
    if (-not $IsWindows) { return }
    $w = 0
    $h = 0
    try {
        $w = [int]$Host.UI.RawUI.WindowSize.Width
        $h = [int]$Host.UI.RawUI.WindowSize.Height
    }
    catch {
        Write-Verbose "Sync-Win11IsoSpectreConsoleDimension: WindowSize read failed: $($_.Exception.Message)"
        $w = [int]$script:Win11IsoAssumedTerminalCols
        $h = [int]$script:Win11IsoAssumedTerminalRows
    }
    if ($w -le 0) { $w = [int]$script:Win11IsoAssumedTerminalCols }
    if ($h -le 0) { $h = [int]$script:Win11IsoAssumedTerminalRows }
    $w = [Math]::Clamp($w, 40, 512)
    $h = [Math]::Clamp($h, 10, 200)
    try {
        [Spectre.Console.AnsiConsole]::Console.Profile.Width = $w
        [Spectre.Console.AnsiConsole]::Console.Profile.Height = $h
    }
    catch {
        Write-Verbose "Sync-Win11IsoSpectreConsoleDimension (AnsiConsole): $($_.Exception.Message)"
    }
    try {
        $m = Get-Module PwshSpectreConsole -ErrorAction SilentlyContinue
        if (-not $m) { return }
        & $m {
            param([int]$WW, [int]$HH)
            if ($null -ne $script:SpectreConsole) {
                $script:SpectreConsole.Profile.Width = $WW
                $script:SpectreConsole.Profile.Height = $HH
            }
        } $w $h
    }
    catch {
        Write-Verbose "Sync-Win11IsoSpectreConsoleDimension (PwshSpectreConsole writer): $($_.Exception.Message)"
    }
}

function Initialize-Spectre {
    <# <summary>Import PwshSpectreConsole from %TEMP%\Win11ISO_dependency_cache\PSGallery (Save-Module) or download once; cache is not deleted at exit.</summary> #>
    $savedVerbose = $VerbosePreference
    try {
        $VerbosePreference = 'SilentlyContinue'
        Get-Module PwshSpectreConsole -ErrorAction SilentlyContinue | Remove-Module -Force
    }
    finally {
        $VerbosePreference = $savedVerbose
    }
    if (-not (Get-Command Save-Module -ErrorAction SilentlyContinue)) {
        throw 'Save-Module was not found (PowerShellGet). Install-Module PowerShellGet -Scope CurrentUser once, or use a full PowerShell 7 install that includes package commands.'
    }
    $galleryCache = Join-Path (Get-Win11IsoDependencyCacheRoot) 'PSGallery'
    $null = New-Item -ItemType Directory -Path $galleryCache -Force
    $savedVerbose = $VerbosePreference
    $savedProgress = $ProgressPreference
    try {
        $VerbosePreference = 'SilentlyContinue'
        $ProgressPreference = 'SilentlyContinue'
        $manifest = $null
        $modRoot = Join-Path $galleryCache 'PwshSpectreConsole'
        if (Test-Path -LiteralPath $modRoot) {
            $manifest = @(Get-ChildItem -LiteralPath $modRoot -Recurse -Filter 'PwshSpectreConsole.psd1' -File -ErrorAction SilentlyContinue | Sort-Object FullName -Descending)[0]
        }
        if ($manifest) {
            try {
                Import-Module -Name $manifest.FullName -Force -Global -ErrorAction Stop
                LogVerbose "PwshSpectreConsole loaded from dependency cache ($($manifest.DirectoryName))."
            }
            catch {
                Write-Verbose "Cached PwshSpectreConsole import failed; re-saving from gallery: $($_.Exception.Message)"
                $manifest = $null
            }
        }
        if (-not $manifest) {
            Save-Module -Name PwshSpectreConsole -Path $galleryCache -Repository PSGallery -Force -ErrorAction Stop
            $manifest = @(Get-ChildItem -LiteralPath $galleryCache -Recurse -Filter 'PwshSpectreConsole.psd1' -File | Sort-Object FullName -Descending)[0]
            if (-not $manifest) { throw "PwshSpectreConsole.psd1 not found under $galleryCache after Save-Module." }
            Import-Module -Name $manifest.FullName -Force -Global -ErrorAction Stop
        }
    }
    finally {
        $VerbosePreference = $savedVerbose
        $ProgressPreference = $savedProgress
    }
    Sync-Win11IsoSpectreConsoleDimension
}

function Invoke-SpectreConsoleTextPrompt {
    <# <summary>Shows a Spectre.Console text prompt with async polling so Ctrl+C still works (same pattern as PwshSpectreConsole).</summary> #>
    param([Parameter(Mandatory)]$Prompt)
    $cts = [System.Threading.CancellationTokenSource]::new()
    $task = $null
    try {
        $task = $Prompt.ShowAsync([Spectre.Console.AnsiConsole]::Console, $cts.Token)
        while (-not $task.AsyncWaitHandle.WaitOne(200)) { }
        if (-not $task.IsCanceled) {
            return $task.GetAwaiter().GetResult()
        }
    }
    finally {
        $cts.Cancel()
        if ($null -ne $task) { $task.Dispose() }
    }
}

function Set-Win11IsoSpectreTextPromptKeepAnswerVisible {
    <# <summary>Keep the prompt (and typed answer) in the scrollback: TextPrompt.ClearOnFinish = false (Spectre.Console ClearOnFinish(false) / spectre.console#1979).</summary> #>
    param([Parameter(Mandatory)]$Prompt)
    try {
        $null = [Spectre.Console.TextPromptExtensions]::ClearOnFinish($Prompt, $false)
        return
    }
    catch { Write-Verbose "TextPromptExtensions.ClearOnFinish: $($_.Exception.Message)" }
    try {
        $p = $Prompt.GetType().GetProperty(
            'ClearOnFinish',
            ([System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Instance))
        if ($null -ne $p -and $p.CanWrite) { $null = $p.SetValue($Prompt, $false) }
    }
    catch { Write-Verbose "TextPrompt.ClearOnFinish property: $($_.Exception.Message)" }
}

function Read-Win11IsoSpectreText {
    <# <summary>Visible text prompt with optional default (same idea as Read-SpectreText); ClearOnFinish off so the exchange stays in the buffer.</summary> #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$DefaultAnswer = ''
    )
    $spectrePrompt = [Spectre.Console.TextPrompt[string]]::new($Message, [System.StringComparer]::Ordinal)
    if (-not [string]::IsNullOrEmpty($DefaultAnswer)) {
        $t = [Spectre.Console.TextPromptExtensions]::DefaultValue($spectrePrompt, $DefaultAnswer)
        $spectrePrompt = [Spectre.Console.TextPromptExtensions]::ShowDefaultValue($t)
    }
    Set-Win11IsoSpectreTextPromptKeepAnswerVisible -Prompt $spectrePrompt
    return Invoke-SpectreConsoleTextPrompt -Prompt $spectrePrompt
}

function Read-SpectreSecretText {
    <# <summary>Masked single-line input (Spectre Secret). Requires PwshSpectreConsole imported.</summary> #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [switch]$AllowEmpty
    )
    $spectrePrompt = [Spectre.Console.TextPrompt[string]]::new($Message, [System.StringComparer]::Ordinal)
    $spectrePrompt = [Spectre.Console.TextPromptExtensions]::Secret($spectrePrompt)
    $spectrePrompt.AllowEmpty = [bool]$AllowEmpty
    Set-Win11IsoSpectreTextPromptKeepAnswerVisible -Prompt $spectrePrompt
    return Invoke-SpectreConsoleTextPrompt -Prompt $spectrePrompt
}

function Read-SpectrePlainText {
    <# <summary>Visible single-line Spectre text prompt (same async pattern as secret prompts).</summary> #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [switch]$AllowEmpty
    )
    $spectrePrompt = [Spectre.Console.TextPrompt[string]]::new($Message, [System.StringComparer]::Ordinal)
    $spectrePrompt.AllowEmpty = [bool]$AllowEmpty
    Set-Win11IsoSpectreTextPromptKeepAnswerVisible -Prompt $spectrePrompt
    return Invoke-SpectreConsoleTextPrompt -Prompt $spectrePrompt
}

function Confirm-Win11IsoTypedDestructiveAcknowledgment {
    <# <summary>Requires typing the phrase YES (capital letters); empty input cancels. Prompt stays visible when Spectre supports TextPrompt.ClearOnFinish.</summary> #>
    param(
        [Parameter(Mandatory)][string]$PanelHeader,
        [Parameter(Mandatory)][string]$PanelBodyMarkup,
        [string]$RequiredPhrase = 'YES'
    )
    Write-SpectreSpacing
    $null = Format-SpectrePanel -Data $PanelBodyMarkup -Header $PanelHeader -Border Double -Color Red -Expand | Out-SpectreHost | Out-Host
    Write-SpectreSpacing
    while ($true) {
        $confirmMessage = @(
            "[bold]To confirm, type[/] [bold white]$RequiredPhrase[/] [bold]and press Enter.[/]"
            '[dim]Those three letters, capitals only. Leave the line empty to cancel.[/]'
        ) -join ' '
        $typed = Read-SpectrePlainText -Message $confirmMessage -AllowEmpty
        if ([string]::IsNullOrWhiteSpace($typed)) {
            $null = Format-SpectrePanel -Data '[yellow]Nothing entered — cancelled.[/]' `
                -Header '[bold yellow]Not confirmed[/]' -Border Rounded -Color Yellow -Expand | Out-SpectreHost | Out-Host
            return $false
        }
        if ($typed -ceq $RequiredPhrase) { return $true }
        $null = Format-SpectrePanel -Data "[red]That was not[/] [bold white]$RequiredPhrase[/][red].[/] [dim]Try again, or leave the line empty to cancel.[/]" `
            -Header '[bold red]Try again[/]' -Border Rounded -Color Red -Expand | Out-SpectreHost | Out-Host
    }
}

function Test-Win11IsoVerboseLogging {
    <# <summary>True when the script was started with -Verbose ($VerbosePreference is Continue).</summary> #>
    return ($VerbosePreference -eq 'Continue')
}

function Invoke-Win11IsoLogStreamFlushUnlessVerbose {
    <#
    <summary>
    Flush stdout/stderr after batched Spectre log lines unless -Verbose is set.
    This makes normal output appear promptly without clearing terminal scrollback.
    </summary>
    #>
    if (Test-Win11IsoVerboseLogging) { return }
    try { [System.Console]::Out.Flush() }
    catch { Write-Verbose "Console.Out.Flush: $($_.Exception.Message)" }
    try { [System.Console]::Error.Flush() }
    catch { Write-Verbose "Console.Error.Flush: $($_.Exception.Message)" }
}

function Get-Win11IsoLogTimestampPrefix {
    if (-not (Test-Win11IsoVerboseLogging)) { return '' }
    return "[grey]$((Get-Date).ToString('HH:mm:ss'))[/] "
}

# Spectre.Console's Profile.Width setter throws "Console width must be greater
# than zero" when no real console is attached. $script:UseSpectre
# starts true; the first failed render latches it to false so subsequent calls
# go straight to plain stdout. Detected once, not retried per call.
$script:UseSpectre = $true

# Persistent build-log sink state. Declared at module scope so reads are
# StrictMode-safe (reading an unset variable throws under Set-StrictMode).
$script:WinMintBuildLogInit = $false
$script:WinMintBuildLogPath = $null

function Write-WinMintConsoleLine {
    param([string]$Markup, [string]$Plain)
    # Persistent build log: mirror every line to output\WinMint-Build.log in real
    # time, before any console/handler branching, so the build is always tailable
    # (Get-Content -Wait) regardless of headless vs interactive. Lazy-init per
    # process truncates it once at the first log line = a fresh log per build.
    if (-not $script:WinMintBuildLogInit) {
        $script:WinMintBuildLogInit = $true
        try {
            $script:WinMintBuildLogPath = Join-Path (Get-WinMintOutputDirectory) 'WinMint-Build.log'
            Set-Content -LiteralPath $script:WinMintBuildLogPath -Value "WinMint build log $(Get-Date -Format o)" -ErrorAction Stop
        }
        catch { $script:WinMintBuildLogPath = $null }
    }
    if ($script:WinMintBuildLogPath) {
        try { Add-Content -LiteralPath $script:WinMintBuildLogPath -Value $Plain -ErrorAction Stop } catch { }
    }
    # When a progress handler is active (headless/GUI/JSON-driven builds), that
    # handler owns console presentation and re-emits every forwarded Log line, so
    # writing here too would print each line twice. Interactive console builds set
    # no handler, leaving this as the sole console sink.
    if ($null -ne (Get-Variable -Name WinMintProgressHandler -Scope Script -ValueOnly -ErrorAction SilentlyContinue)) {
        return
    }
    if ($script:UseSpectre) {
        try { $null = Write-SpectreHost $Markup; return }
        catch { $script:UseSpectre = $false }
    }
    # Write-Host (not Write-Output): keeps the message off the success stream so it
    # cannot pollute function return values when Log/LogOK is called inside a
    # function whose pscustomobject return is later property-accessed.
    Write-Host $Plain
}

function Send-WinMintConsoleLogToProgressHandler {
    param(
        [ValidateSet('Info','OK','Warn','Error','Section')]
        [string]$Level = 'Info',
        [Parameter(Mandatory)][string]$Message
    )
    $handler = Get-Variable -Name WinMintProgressHandler -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $handler) { return }
    Write-WinMintProgress -Level $Level -Message $Message -ProgressHandler $handler
}

function Log {
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    $ts = Get-Win11IsoLogTimestampPrefix
    Write-WinMintConsoleLine "${ts}[cyan1]>[/] [white]$Message[/]" "> $Message"
    Send-WinMintConsoleLogToProgressHandler -Level Info -Message $Message
    Invoke-Win11IsoLogStreamFlushUnlessVerbose
}

function LogOK {
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    $ts = Get-Win11IsoLogTimestampPrefix
    Write-WinMintConsoleLine "${ts}[green]+[/] [silver]$Message[/]" "+ $Message"
    Send-WinMintConsoleLogToProgressHandler -Level OK -Message $Message
    Invoke-Win11IsoLogStreamFlushUnlessVerbose
}

function LogWarn {
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    $ts = Get-Win11IsoLogTimestampPrefix
    Write-WinMintConsoleLine "${ts}[yellow]![/] [white]$Message[/]" "! $Message"
    Send-WinMintConsoleLogToProgressHandler -Level Warn -Message $Message
    Invoke-Win11IsoLogStreamFlushUnlessVerbose
}

function LogErr {
    <# <summary>Fatal or caught failure line; with -Verbose appends position/stack hints for ErrorRecords.</summary> #>
    param([Parameter(Mandatory, Position = 0)]$Message)
    $ts = Get-Win11IsoLogTimestampPrefix
    if ($Message -is [System.Management.Automation.ErrorRecord]) {
        $ex = $Message.Exception
        $line = if ($null -ne $ex -and -not [string]::IsNullOrEmpty($ex.Message)) { $ex.Message } else { $Message.ToString() }
        Write-WinMintConsoleLine "${ts}[red]x[/] [white]$([Spectre.Console.Markup]::Escape($line))[/]" "x $line"
        Send-WinMintConsoleLogToProgressHandler -Level Error -Message $line
        if (Test-Win11IsoVerboseLogging) {
            if ($Message.InvocationInfo.PositionMessage) {
                Write-WinMintConsoleLine "[dim]$([Spectre.Console.Markup]::Escape($Message.InvocationInfo.PositionMessage))[/]" $Message.InvocationInfo.PositionMessage
            }
            if ($Message.ScriptStackTrace) {
                Write-WinMintConsoleLine "[dim]$([Spectre.Console.Markup]::Escape($Message.ScriptStackTrace))[/]" $Message.ScriptStackTrace
            }
        }
        Microsoft.PowerShell.Utility\Write-Verbose -Message ($Message | Format-List * -Force | Out-String)
    }
    else {
        $plain = "$Message"
        Write-WinMintConsoleLine "${ts}[red]x[/] [white]$([Spectre.Console.Markup]::Escape($plain))[/]" "x $plain"
        Send-WinMintConsoleLogToProgressHandler -Level Error -Message $plain
        if (Test-Win11IsoVerboseLogging) {
            Microsoft.PowerShell.Utility\Write-Verbose -Message $plain
        }
    }
    Invoke-Win11IsoLogStreamFlushUnlessVerbose
}

function LogDry {
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    $ts = Get-Win11IsoLogTimestampPrefix
    Write-WinMintConsoleLine "${ts}[darkorange3]dry[/] [silver]$Message[/]" "dry $Message"
    Send-WinMintConsoleLogToProgressHandler -Level Info -Message "Dry run: $Message"
    Invoke-Win11IsoLogStreamFlushUnlessVerbose
}

function LogVerbose {
    <# <summary>Technical detail only when -Verbose is set (Spectre dim line only; no Write-Verbose to avoid doubling and cmdlet noise).</summary> #>
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    if (-not (Test-Win11IsoVerboseLogging)) { return }
    $null = Write-SpectreHost "[grey]$((Get-Date).ToString('HH:mm:ss'))[/] [dim]$Message[/]"
}

