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
    if (Get-Command Apply-WinMintSpectreLogTheme -ErrorAction SilentlyContinue) {
        Apply-WinMintSpectreLogTheme
    }
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

# Spectre.Console's Profile.Width setter throws "Console width must be greater
# than zero" when no real console is attached. $script:UseSpectre
# starts true; the first failed render latches it to false so subsequent calls
# go straight to plain stdout. Detected once, not retried per call.
$script:UseSpectre = $true

# Dual-channel build log state (StrictMode-safe script defaults).
$script:WinMintBuildLogInit = $false
$script:WinMintBuildVerboseLogPath = $null
$script:WinMintBuildLogPath = $null
$script:WinMintHumanConsoleMuted = $false

function Test-WinMintHumanConsoleMuted {
    return [bool]$script:WinMintHumanConsoleMuted
}

function Set-WinMintHumanConsoleMuted {
    param([bool]$Muted)
    $script:WinMintHumanConsoleMuted = $Muted
}

function Get-WinMintBuildVerboseLogPath {
    if ($script:WinMintBuildVerboseLogPath) { return $script:WinMintBuildVerboseLogPath }
    return (Join-Path (Get-WinMintOutputDirectory) 'WinMint-Build.verbose.log')
}

function Initialize-WinMintBuildLogSinks {
    if ($script:WinMintBuildLogInit) { return }
    $script:WinMintBuildLogInit = $true
    try {
        $out = Get-WinMintOutputDirectory
        $script:WinMintBuildVerboseLogPath = Join-Path $out 'WinMint-Build.verbose.log'
        $script:WinMintBuildLogPath = Join-Path $out 'WinMint-Build.log'
        $header = @(
            "WinMint verbose build log $(Get-Date -Format o)"
            "Canonical path: $($script:WinMintBuildVerboseLogPath)"
        ) -join [Environment]::NewLine
        Set-Content -LiteralPath $script:WinMintBuildVerboseLogPath -Value $header -Encoding utf8 -ErrorAction Stop
        # ponytail: mirror for Get-Content -Wait muscle memory; drop when callers move to .verbose.log
        Set-Content -LiteralPath $script:WinMintBuildLogPath -Value $header -Encoding utf8 -ErrorAction Stop
        if (-not (Test-WinMintHumanConsoleMuted)) {
            if (Get-Command Write-WinMintLogSessionChrome -ErrorAction SilentlyContinue) {
                Write-WinMintLogSessionChrome -VerboseLogPath $script:WinMintBuildVerboseLogPath
            }
            else {
                $hint = "Verbose log: $($script:WinMintBuildVerboseLogPath)"
                Write-WinMintHumanConsoleLine -Markup "[dim]$hint[/]" -Plain $hint
            }
        }
    }
    catch {
        $script:WinMintBuildVerboseLogPath = $null
        $script:WinMintBuildLogPath = $null
    }
}

function Write-WinMintVerboseLogLine {
    param([Parameter(Mandatory)][string]$Line)
    Initialize-WinMintBuildLogSinks
    foreach ($path in @($script:WinMintBuildVerboseLogPath, $script:WinMintBuildLogPath)) {
        if (-not $path) { continue }
        try { Add-Content -LiteralPath $path -Value $Line -Encoding utf8 -ErrorAction Stop } catch { }
    }
}

function Write-WinMintHumanConsoleLine {
    param([string]$Markup, [string]$Plain)
    if (Test-WinMintHumanConsoleMuted) { return }
    if ($script:UseSpectre -and (Get-Command Write-SpectreHost -ErrorAction SilentlyContinue)) {
        try { $null = Write-SpectreHost $Markup; return }
        catch { $script:UseSpectre = $false }
    }
    # Write-Host (not Write-Output): keeps the message off the success stream.
    Write-Host $Plain
}

function Write-WinMintBuildLog {
    <#
    <summary>
    Dual-channel fan-out: always append timestamped plain lines to the verbose
    file (and WinMint-Build.log mirror); optionally render Spectre markup on the
    human console unless muted (-Quiet/-Json/UI bridge).
    </summary>
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'DRY', 'SECTION', 'VERBOSE')]
        [string]$Level,
        [Parameter(Mandatory)][string]$Message,
        [string]$Markup = '',
        [string]$PlainGlyph = '',
        [switch]$Human
    )
    $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    Write-WinMintVerboseLogLine "$ts $Level $Message"
    if (-not $Human) { return }
    if ([string]::IsNullOrEmpty($Markup)) {
        $Markup = "[white]$(Escape-WinMintSpectreMarkup $Message)[/]"
        $PlainGlyph = $Message
    }
    Write-WinMintHumanConsoleLine -Markup $Markup -Plain $PlainGlyph
}

function Send-WinMintConsoleLogToProgressHandler {
    param(
        [ValidateSet('Info', 'OK', 'Warn', 'Error', 'Section')]
        [string]$Level = 'Info',
        [Parameter(Mandatory)][string]$Message,
        [string]$Stage = ''
    )
    $handler = Get-Variable -Name WinMintProgressHandler -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $handler) { return }
    # Events only — handler must not own console glyphs (avoids double-print).
    & $handler ([pscustomobject]@{
            Time    = [DateTimeOffset]::Now.ToString('o')
            Stage   = $Stage
            Level   = $Level
            Message = $Message
        })
}

# Compat shim for any residual callers. Formatters / Log* live in Logging.ps1.
function Write-WinMintConsoleLine {
    param([string]$Markup, [string]$Plain)
    Write-WinMintVerboseLogLine $Plain
    Write-WinMintHumanConsoleLine -Markup $Markup -Plain $Plain
}

