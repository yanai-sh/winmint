#Requires -Version 7.6
<#
.SYNOPSIS
  Engine Spectre build-log util — One Half Dark human chrome; file channel stays plain via Host sinks.
  Theme/palette: src/runtime/WinMint.ConsoleTheme.ps1
#>

$script:WinMintConsoleThemePath = Join-Path $PSScriptRoot '..\..\..\WinMint.ConsoleTheme.ps1'
if (-not (Get-Command Get-WinMintConsoleTheme -ErrorAction SilentlyContinue)) {
    . $script:WinMintConsoleThemePath
}

$script:WinMintConsoleStatusSpinner = 'Aesthetic'
$script:WinMintConsoleStatusSpinnerFallback = 'Dots2'
$script:WinMintConsoleRuleWidthPercent = 92
# Session chrome panel at most once per process (sinks also gate on WinMintBuildLogInit).
$script:WinMintLogSessionChromeShown = $false

function Escape-WinMintSpectreMarkup {
    param([Parameter(Mandatory)][string]$Text)
    try { return [Spectre.Console.Markup]::Escape($Text) }
    catch { return ($Text -replace '\[', '[[') }
}

function Apply-WinMintSpectreLogTheme {
    <# <summary>Accent + table defaults after PwshSpectreConsole import (One Half Dark).</summary> #>
    if (-not (Get-Command Set-SpectreColors -ErrorAction SilentlyContinue)) { return }
    $accent = Get-WinMintConsoleAccentColor
    $header = Get-WinMintConsoleTheme Blue
    $text = Get-WinMintConsoleTheme FgMuted
    $dim = Get-WinMintConsoleTheme FgDim
    try {
        Set-SpectreColors `
            -AccentColor $accent `
            -DefaultValueColor $dim `
            -DefaultTableHeaderColor $header `
            -DefaultTableTextColor $text `
            -ErrorAction Stop
    }
    catch {
        try {
            Set-SpectreColors -AccentColor $accent -DefaultValueColor $dim -ErrorAction Stop
        }
        catch {
            Write-Verbose "Apply-WinMintSpectreLogTheme: $($_.Exception.Message)"
        }
    }
}

function Out-WinMintSpectreRenderable {
    <# <summary>Render a Spectre widget to the human console (respects mute / UseSpectre).</summary> #>
    param([Parameter(Mandatory)]$Renderable)
    if (Test-WinMintHumanConsoleMuted) { return }
    if (-not $script:UseSpectre) { return }
    if (-not (Get-Command Out-SpectreHost -ErrorAction SilentlyContinue)) { return }
    try {
        $null = $Renderable | Out-SpectreHost | Out-Host
    }
    catch {
        $script:UseSpectre = $false
        Write-Verbose "Out-WinMintSpectreRenderable: $($_.Exception.Message)"
    }
}

function Format-WinMintLogMarkup {
    <#
    .SYNOPSIS
      High-fidelity Spectre log line (shared theme formatter + Spectre escape).
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'DRY', 'SECTION', 'VERBOSE')]
        [string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    return (Format-WinMintConsoleLineMarkup -Level $Level -Message $Message -SafeMessage (Escape-WinMintSpectreMarkup $Message))
}

function Format-WinMintLogPlainGlyph {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'DRY', 'SECTION', 'VERBOSE')]
        [string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    return (Format-WinMintConsolePlainGlyph -Level $Level -Message $Message)
}

function Get-WinMintSpectreStatusTitle {
    param([Parameter(Mandatory)][string]$Description)
    $safe = Escape-WinMintSpectreMarkup $Description
    $blue = Get-WinMintConsoleTheme Blue
    $fg = Get-WinMintConsoleTheme Fg
    $run = New-WinMintConsoleBadgeMarkup -Label ' RUN ' -AccentHex $blue
    return "[$blue]│[/] $run  [$fg]$safe[/]"
}

function Write-WinMintLogSessionChrome {
    <#
    <summary>
    Compact dual-channel banner (Rounded panel). Called once when verbose sinks open.
    </summary>
    #>
    param(
        [Parameter(Mandatory)][string]$VerboseLogPath,
        [string]$Subtitle = 'Dual-channel build log'
    )
    if (Test-WinMintHumanConsoleMuted) { return }
    if ($script:WinMintLogSessionChromeShown) { return }
    $script:WinMintLogSessionChromeShown = $true
    $safePath = Escape-WinMintSpectreMarkup $VerboseLogPath
    $safeSub = Escape-WinMintSpectreMarkup $Subtitle
    $blue = Get-WinMintConsoleTheme Blue
    $cyan = Get-WinMintConsoleTheme Cyan
    $dim = Get-WinMintConsoleTheme FgDim
    $muted = Get-WinMintConsoleTheme FgMuted
    $body = @(
        "[$muted]$safeSub[/]"
        ''
        "[$dim]Human[/]   One Half Dark  [dim]·[/]  sparse Spectre"
        "[$dim]File[/]    [$cyan]$safePath[/]"
    ) -join "`n"

    if ($script:UseSpectre -and (Get-Command Format-SpectrePanel -ErrorAction SilentlyContinue)) {
        try {
            if (Get-Command Write-SpectreSpacing -ErrorAction SilentlyContinue) { Write-SpectreSpacing }
            $panel = Format-SpectrePanel -Data $body `
                -Header "[bold $blue]WinMint[/] [$dim]·[/] [$muted]logging[/]" `
                -Border Rounded `
                -Color (Get-WinMintConsoleAccentColor) `
                -Expand
            Out-WinMintSpectreRenderable -Renderable $panel
            return
        }
        catch {
            Write-Verbose "Write-WinMintLogSessionChrome panel failed: $($_.Exception.Message)"
        }
    }
    Write-WinMintHumanConsoleLine -Markup "[$dim]Verbose log: $safePath[/]" -Plain "Verbose log: $VerboseLogPath"
}

function Write-WinMintLogAlertPanel {
    <#
    <summary>
    Rounded alert panel for WARN/ERROR (human only). Optional Format-SpectreException body.
    </summary>
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('WARN', 'ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Message,
        $Exception = $null
    )
    if (Test-WinMintHumanConsoleMuted) { return }
    if (-not $script:UseSpectre) { return }
    if (-not (Get-Command Format-SpectrePanel -ErrorAction SilentlyContinue)) { return }

    $safe = Escape-WinMintSpectreMarkup $Message
    $style = Get-WinMintConsoleLevelStyle -Level $Level
    $borderColor = if ($Level -eq 'ERROR') { (Get-WinMintConsoleTheme Red) } else { (Get-WinMintConsoleTheme Yellow) }
    $header = "$([string]$style.BadgeMarkup)  [$([string]$style.MessageColor)]$safe[/]"
    $data = $null

    if ($null -ne $Exception -and (Get-Command Format-SpectreException -ErrorAction SilentlyContinue)) {
        try {
            $data = Format-SpectreException -Exception $Exception -ExceptionFormat ShortenEverything -ExceptionStyle @{
                Message       = (Get-WinMintConsoleTheme Red)
                Exception     = (Get-WinMintConsoleTheme Fg)
                Method        = (Get-WinMintConsoleTheme Cyan)
                ParameterType = (Get-WinMintConsoleTheme Blue)
                ParameterName = (Get-WinMintConsoleTheme FgMuted)
                Path          = (Get-WinMintConsoleTheme Yellow)
                LineNumber    = (Get-WinMintConsoleTheme Blue)
                Dimmed        = (Get-WinMintConsoleTheme FgDim)
                NonEmphasized = (Get-WinMintConsoleTheme FgMuted)
            }
        }
        catch {
            Write-Verbose "Format-SpectreException failed: $($_.Exception.Message)"
        }
    }
    if ($null -eq $data) {
        $data = "[$([string]$style.MessageColor)]$safe[/]"
    }

    try {
        $panel = Format-SpectrePanel -Data $data -Header $header -Border Rounded -Color $borderColor -Expand
        Out-WinMintSpectreRenderable -Renderable $panel
    }
    catch {
        Write-Verbose "Write-WinMintLogAlertPanel: $($_.Exception.Message)"
    }
}

function Write-WinMintLogSummaryPanel {
    <# <summary>End-of-phase key/value summary in a Rounded accent panel.</summary> #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [string]$Color = ''
    )
    if (Test-WinMintHumanConsoleMuted) { return }
    if (-not $script:UseSpectre) { return }
    if (-not (Get-Command Format-SpectreTable -ErrorAction SilentlyContinue)) { return }
    if (-not (Get-Command Format-SpectrePanel -ErrorAction SilentlyContinue)) { return }

    $accent = if (-not [string]::IsNullOrWhiteSpace($Color)) { $Color } else { Get-WinMintConsoleAccentColor }
    $safeTitle = Escape-WinMintSpectreMarkup $Title
    $cyan = Get-WinMintConsoleTheme Cyan
    $fg = Get-WinMintConsoleTheme Fg
    $gutter = Get-WinMintConsoleTheme Gutter
    try {
        $table = Format-SpectreTable -Data $Rows -Property Item, Value -AllowMarkup -HideHeaders `
            -Border Minimal -Color $gutter -Expand
        $panel = Format-SpectrePanel -Data $table `
            -Header "[bold $cyan]◆[/] [bold $fg]$safeTitle[/]" `
            -Border Rounded -Color $accent -Expand
        if (Get-Command Write-SpectreSpacing -ErrorAction SilentlyContinue) { Write-SpectreSpacing }
        Out-WinMintSpectreRenderable -Renderable $panel
    }
    catch {
        Write-Verbose "Write-WinMintLogSummaryPanel: $($_.Exception.Message)"
    }
}

function Write-WinMintLogSectionRule {
    <# <summary>Fluent phase rule (human console only).</summary> #>
    param([Parameter(Mandatory)][string]$Title)
    if (Test-WinMintHumanConsoleMuted) { return }
    $accent = Get-WinMintConsoleAccentColor
    $lineColor = Get-WinMintConsoleRuleLineColor
    $plain = "◆ $Title"
    if ($script:UseSpectre -and (Get-Command Write-SpectreRule -ErrorAction SilentlyContinue)) {
        try {
            if (Get-Command Write-SpectreSpacing -ErrorAction SilentlyContinue) { Write-SpectreSpacing }
            $ruleParams = @{
                Title     = $plain
                Color     = $accent
                LineColor = $lineColor
            }
            $cmd = Get-Command Write-SpectreRule
            $pct = [int]$script:WinMintConsoleRuleWidthPercent
            if ($pct -lt 1 -or $pct -gt 100) { $pct = 92 }
            if ($cmd.Parameters.ContainsKey('WidthPercent')) {
                $ruleParams['WidthPercent'] = $pct
            }
            if ($cmd.Parameters.ContainsKey('Alignment')) {
                $ruleParams['Alignment'] = 'Center'
            }
            $null = Write-SpectreRule @ruleParams
            return
        }
        catch {
            $script:UseSpectre = $false
        }
    }
    Write-Host $plain
}

function Invoke-WinMintSpectreStatus {
    <#
    <summary>
    Aesthetic status spinner around a scriptblock. Falls back to Dots2, then bare invoke.
    </summary>
    #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )
    if (-not (Get-Command Invoke-SpectreCommandWithStatus -ErrorAction SilentlyContinue)) {
        & $ScriptBlock
        return
    }
    $statusTitle = Get-WinMintSpectreStatusTitle -Description $Title
    $accent = Get-WinMintConsoleAccentColor
    $work = {
        Invoke-WinMintSpectreQuiet -ScriptBlock $ScriptBlock
    }.GetNewClosure()
    foreach ($spinner in @($script:WinMintConsoleStatusSpinner, $script:WinMintConsoleStatusSpinnerFallback, 'Dots2')) {
        if ([string]::IsNullOrWhiteSpace($spinner)) { continue }
        try {
            $null = Invoke-SpectreCommandWithStatus -Spinner $spinner -Title $statusTitle -Color $accent -ScriptBlock $work
            return
        }
        catch {
            Write-Verbose "Invoke-WinMintSpectreStatus spinner '$spinner' failed: $($_.Exception.Message)"
        }
    }
    & $ScriptBlock
}

function Invoke-WinMintSpectreProgress {
    <#
    <summary>
    Themed indeterminate/determinate progress for long DISM-class steps.
    ScriptBlock receives no args; updates go through `$script:DismProgressCallback`.
    </summary>
    #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )
    if (-not (Get-Command Invoke-SpectreCommandWithProgress -ErrorAction SilentlyContinue)) {
        & $ScriptBlock
        return
    }
    $taskTitle = Get-WinMintSpectreStatusTitle -Description $Title
    try {
        Invoke-SpectreCommandWithProgress -ScriptBlock ({
                param([Spectre.Console.ProgressContext]$Context)
                $task = $Context.AddTask($taskTitle)
                $task.IsIndeterminate = $true
                $script:DismProgressCallback = {
                    param([double]$Pct)
                    $task.IsIndeterminate = $false
                    $task.Value = $Pct
                }.GetNewClosure()
                try {
                    Invoke-WinMintSpectreQuiet -ScriptBlock $ScriptBlock
                }
                finally {
                    $task.Value = 100
                    $script:DismProgressCallback = $null
                }
            }.GetNewClosure())
        return
    }
    catch {
        Write-Verbose "Invoke-WinMintSpectreProgress failed: $($_.Exception.Message)"
    }
    & $ScriptBlock
}

function Write-WinMintLog {
    <#
    <summary>
    Single log entry: verbose file always; Spectre human line when -Human; optional progress event.
    </summary>
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'DRY', 'SECTION', 'VERBOSE')]
        [string]$Level,
        [Parameter(Mandatory)][string]$Message,
        [switch]$Human,
        [ValidateSet('Info', 'OK', 'Warn', 'Error', 'Section')]
        [string]$ProgressLevel,
        [string]$ProgressStage = ''
    )
    if ($Human) {
        Write-WinMintBuildLog -Level $Level -Message $Message -Human `
            -Markup (Format-WinMintLogMarkup -Level $Level -Message $Message) `
            -PlainGlyph (Format-WinMintLogPlainGlyph -Level $Level -Message $Message)
    }
    else {
        Write-WinMintBuildLog -Level $Level -Message $Message
    }
    if ($PSBoundParameters.ContainsKey('ProgressLevel') -and -not [string]::IsNullOrWhiteSpace($ProgressLevel)) {
        Send-WinMintConsoleLogToProgressHandler -Level $ProgressLevel -Message $Message -Stage $ProgressStage
    }
}

function Log {
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    Write-WinMintLog -Level INFO -Message $Message -Human -ProgressLevel Info
    Invoke-Win11IsoLogStreamFlushUnlessVerbose
}

function LogOK {
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    Write-WinMintLog -Level OK -Message $Message -Human -ProgressLevel OK
    Invoke-Win11IsoLogStreamFlushUnlessVerbose
}

function LogWarn {
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    Write-WinMintLog -Level WARN -Message $Message -Human -ProgressLevel Warn
    Invoke-Win11IsoLogStreamFlushUnlessVerbose
}

function LogErr {
    <#
    <summary>
    Failure: verbose file always; human gets a Rounded alert panel (Format-SpectreException when ErrorRecord).
    </summary>
    #>
    param([Parameter(Mandatory, Position = 0)]$Message)
    if ($Message -is [System.Management.Automation.ErrorRecord]) {
        $ex = $Message.Exception
        $line = if ($null -ne $ex -and -not [string]::IsNullOrEmpty($ex.Message)) { $ex.Message } else { $Message.ToString() }
        Write-WinMintBuildLog -Level ERROR -Message $line
        Write-WinMintLogAlertPanel -Level ERROR -Message $line -Exception $Message
        Send-WinMintConsoleLogToProgressHandler -Level Error -Message $line
        if ($Message.InvocationInfo.PositionMessage) {
            Write-WinMintBuildLog -Level VERBOSE -Message $Message.InvocationInfo.PositionMessage
        }
        if ($Message.ScriptStackTrace) {
            Write-WinMintBuildLog -Level VERBOSE -Message $Message.ScriptStackTrace
        }
        Microsoft.PowerShell.Utility\Write-Verbose -Message ($Message | Format-List * -Force | Out-String)
    }
    else {
        $plainMsg = "$Message"
        Write-WinMintBuildLog -Level ERROR -Message $plainMsg
        Write-WinMintLogAlertPanel -Level ERROR -Message $plainMsg
        Send-WinMintConsoleLogToProgressHandler -Level Error -Message $plainMsg
        if (Test-Win11IsoVerboseLogging) {
            Microsoft.PowerShell.Utility\Write-Verbose -Message $plainMsg
        }
    }
    Invoke-Win11IsoLogStreamFlushUnlessVerbose
}

function LogDry {
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    Write-WinMintLog -Level DRY -Message $Message -Human
    Send-WinMintConsoleLogToProgressHandler -Level Info -Message "Dry run: $Message"
    Invoke-Win11IsoLogStreamFlushUnlessVerbose
}

function LogSection {
    <# <summary>Human phase rule + verbose SECTION line + Section progress event.</summary> #>
    param([Parameter(Mandatory, Position = 0)][string]$Title)
    Write-WinMintBuildLog -Level SECTION -Message $Title
    Write-WinMintLogSectionRule -Title $Title
    Send-WinMintConsoleLogToProgressHandler -Level Section -Message $Title -Stage $Title
    Invoke-Win11IsoLogStreamFlushUnlessVerbose
}

function LogVerbose {
    <# <summary>Always writes the verbose file; mirrors to dim Spectre console only with -Verbose.</summary> #>
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    Write-WinMintBuildLog -Level VERBOSE -Message $Message
    if (Test-Win11IsoVerboseLogging -and -not (Test-WinMintHumanConsoleMuted)) {
        Write-WinMintHumanConsoleLine `
            -Markup (Format-WinMintLogMarkup -Level VERBOSE -Message $Message) `
            -Plain (Format-WinMintLogPlainGlyph -Level VERBOSE -Message $Message)
    }
}
