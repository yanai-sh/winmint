#Requires -Version 7.3

function Write-SpectreSpacing {
    <# <summary>One blank line via Spectre.Console (keeps all visual output on the Spectre stack; no Host.UI).</summary> #>
    try {
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    catch {
        Write-Verbose "Write-SpectreSpacing: $($_.Exception.Message)"
    }
}

function Write-SectionHeader {
    <#
    <summary>
    Standard section break: one blank line, rule title, optional dim cue line,
    spacing, then flush.
    </summary>
    #>
    param(
        [ValidateNotNullOrEmpty()][string]$Title,
        [ValidateSet('Cyan', 'Yellow', 'Green', 'Red', 'Grey')][string]$Accent = 'Cyan',
        [ValidateSet('Grey', 'Green', 'Red', 'Yellow', 'Cyan1')][string]$RuleColor = 'Grey',
        [string]$DimLine = '',
        [switch]$OmitLeadingBlank,
        [switch]$Compact
    )
    $titleColor = switch ($Accent) {
        'Yellow' { [Spectre.Console.Color]::Yellow }
        'Green' { [Spectre.Console.Color]::Green }
        'Red' { [Spectre.Console.Color]::Red }
        'Grey' { [Spectre.Console.Color]::Grey }
        default { [Spectre.Console.Color]::Cyan3 }
    }
    $lineSpectreColor = switch ($RuleColor) {
        'Green' { [Spectre.Console.Color]::Green }
        'Red' { [Spectre.Console.Color]::Red }
        'Yellow' { [Spectre.Console.Color]::Yellow }
        'Cyan1' { [Spectre.Console.Color]::Cyan1 }
        default { [Spectre.Console.Color]::Grey }
    }
    if (-not $script:UseSpectre) {
        Write-Host ''
        Write-Host ('--- ' + $Title + ' ---')
        if (-not [string]::IsNullOrWhiteSpace($DimLine)) { Write-Host $DimLine }
        return
    }
    try {
        if (-not $OmitLeadingBlank) { Write-SpectreSpacing }
        $null = Write-SpectreRule -Title $Title -Color $titleColor -LineColor $lineSpectreColor
        if (-not $Compact) { Write-SpectreSpacing }
        if (-not [string]::IsNullOrWhiteSpace($DimLine)) {
            $null = Write-SpectreHost "[dim]$DimLine[/]"
            if (-not $Compact) { Write-SpectreSpacing }
        }
    } catch {
        $script:UseSpectre = $false
        Write-Host ''
        Write-Host ('--- ' + $Title + ' ---')
        if (-not [string]::IsNullOrWhiteSpace($DimLine)) { Write-Host $DimLine }
    }
    Invoke-Win11IsoLogStreamFlushUnlessVerbose
}

function Write-SpectreKeyValueTable {
    <#
    <summary>
    Titled two-column table with Spectre markup. Call Write-SpectreSpacing
    before this when you want a gap above the table.
    </summary>
    #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [string]$TableColor = 'Grey'
    )
    $null = Format-SpectreTable -Data $Rows -Property Item, Value -AllowMarkup -HideHeaders -Border Rounded `
        -Title $Title -Expand -Color $TableColor | Out-SpectreHost | Out-Host
}

function Get-Win11IsoTerminalWidth {
    <# <summary>Best-effort console width for layout; falls back to Win11IsoAssumedTerminalCols (Windows Terminal default ~120 with Cascadia Mono 12 pt) when RawUI is missing.</summary> #>
    try {
        $w = $Host.UI.RawUI.WindowSize.Width
        if ($w -gt 0) { return [Math]::Max(40, $w) }
    }
    catch { Write-Verbose "Window width read failed: $($_.Exception.Message)" }
    try {
        $w = $Host.UI.RawUI.BufferSize.Width
        if ($w -gt 0) { return [Math]::Max(40, $w) }
    }
    catch { Write-Verbose "Buffer width read failed: $($_.Exception.Message)" }
    return [Math]::Max(40, [int]$script:Win11IsoAssumedTerminalCols)
}

function Get-Win11IsoTerminalHeight {
    <# <summary>Best-effort visible console height in rows; falls back to Win11IsoAssumedTerminalRows (default 30) for splash budgeting when RawUI is missing.</summary> #>
    try {
        $h = $Host.UI.RawUI.WindowSize.Height
        if ($h -gt 0) { return [Math]::Clamp($h, 10, 200) }
    }
    catch { Write-Verbose "Window height read failed: $($_.Exception.Message)" }
    try {
        $h = $Host.UI.RawUI.BufferSize.Height
        if ($h -gt 0) { return [Math]::Clamp($h, 10, 200) }
    }
    catch { Write-Verbose "Buffer height read failed: $($_.Exception.Message)" }
    return [Math]::Clamp([int]$script:Win11IsoAssumedTerminalRows, 10, 200)
}

function Get-CenteredText {
    param([string]$Text, [int]$Width)
    if ($Text.Length -ge $Width) { return $Text.Substring(0, $Width) }
    $lp = [int][Math]::Floor(($Width - $Text.Length) / 2)
    $Text.PadLeft($Text.Length + $lp).PadRight($Width)
}

function Get-Win11IsoHeroFramedBanner {
    <# <summary>Box-drawn banner that scales to MaxWidth so narrow terminals do not wrap mid-logo.</summary> #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][int]$MaxWidth
    )
    $outer = [Math]::Clamp($MaxWidth, 40, 256)
    $inner = $outer - 2
    $h = [string]::new('═', $inner)
    $top = "╔${h}╗"
    $bot = "╚${h}╝"
    $row1 = '║' + (Get-CenteredText -Text $Title -Width $inner) + '║'
    $row2 = '║' + (Get-CenteredText -Text 'autounattend · install.wim · oscdimg · output' -Width $inner) + '║'
    return @($top, $row1, $row2, $bot)
}

function Split-HeroBannerLines {
    param([string]$Raw)
    @(
        $Raw.Trim() -split "`r?`n" |
            ForEach-Object { $_.TrimEnd() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-Win11IsoSplashHeroBanner {
    <# <summary>Pick a pre-embedded hero ASCII tier: ``Normal`` (full logo) or ``Compact`` (narrow card). Framed box when neither fits cols/rows. No external processes.</summary> #>
    param(
        [Parameter(Mandatory)][int]$Cols,
        [Parameter(Mandatory)][int]$Rows,
        [Parameter(Mandatory)][string]$ShortTitle
    )
    $panelSlack = 8
    $reserveBelow = 14
    $budgetRows = [Math]::Max(3, $Rows - $reserveBelow)
    $maxAvail = [Math]::Max(40, $Cols - $panelSlack)

    function Measure-Win11IsoHeroBlock {
        param([AllowEmptyCollection()][string[]]$Lines)
        if (-not $Lines -or $Lines.Count -lt 1) { return @{ MaxW = 0; Count = 0 } }
        $m = 0
        foreach ($ln in $Lines) { if ($ln.Length -gt $m) { $m = $ln.Length } }
        return @{ MaxW = $m; Count = $Lines.Count }
    }

    $tiers = @(
        @{ Name = 'Normal';  Lines = @(Split-HeroBannerLines $script:Win11IsoHeroBannerNormal) },
        @{ Name = 'Compact'; Lines = @(Split-HeroBannerLines $script:Win11IsoHeroBannerCompact) }
    )
    foreach ($tier in $tiers) {
        $lines = @($tier.Lines)
        $stat = Measure-Win11IsoHeroBlock -Lines $lines
        if ($stat.MaxW -lt 1) { continue }
        if ($stat.MaxW -le $maxAvail -and $stat.Count -le $budgetRows) {
            Write-Verbose "Splash hero tier: $($tier.Name) ($($stat.MaxW) cols x $($stat.Count) rows; terminal ${Cols}x${Rows})."
            return $lines
        }
    }
    Write-Verbose "Splash hero tier: framed (terminal ${Cols}x${Rows})."
    return @(Get-Win11IsoHeroFramedBanner -Title $ShortTitle -MaxWidth $Cols)
}
function Get-TerminalBackgroundColor {
    # Query terminal background via OSC 11. Returns '#RRGGBB' string or $null.
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { return $null }
    try {
        [Console]::Write("`e]11;?`a")
        $buf = [System.Text.StringBuilder]::new(64)
        $sw  = [System.Diagnostics.Stopwatch]::StartNew()
        while ($sw.ElapsedMilliseconds -lt 500) {
            if ([Console]::KeyAvailable) {
                $null = $buf.Append([Console]::ReadKey($true).KeyChar)
                $s = $buf.ToString()
                # Terminal responds ESC ] 11 ; rgb:RR/GG/BB BEL  or  ... ESC \
                if ($s[-1] -eq "`a" -or ($s.Length -ge 2 -and $s[-2] -eq "`e" -and $s[-1] -eq '\')) { break }
            } else {
                [System.Threading.Thread]::Sleep(5)
            }
        }
        if ($buf.ToString() -match 'rgb:([0-9a-fA-F]{2,4})/([0-9a-fA-F]{2,4})/([0-9a-fA-F]{2,4})') {
            # Some terminals return 4 hex digits (16-bit per channel) — use high byte only
            $r = [Convert]::ToInt32($Matches[1].Substring(0, 2), 16)
            $g = [Convert]::ToInt32($Matches[2].Substring(0, 2), 16)
            $b = [Convert]::ToInt32($Matches[3].Substring(0, 2), 16)
            return '#{0:X2}{1:X2}{2:X2}' -f $r, $g, $b
        }
    }
    catch { Write-Verbose "Terminal background query failed: $($_.Exception.Message)" }
    return $null
}

function New-Win11IsoCompositedPng {
    # Composite a transparent PNG against a solid background color and write to a temp file.
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$BackgroundHex
    )
    Add-Type -AssemblyName System.Drawing
    $src = [System.Drawing.Image]::FromFile($SourcePath)
    $bmp = [System.Drawing.Bitmap]::new($src.Width, $src.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $ri = [Convert]::ToInt32($BackgroundHex.Substring(1, 2), 16)
        $gi = [Convert]::ToInt32($BackgroundHex.Substring(3, 2), 16)
        $bi = [Convert]::ToInt32($BackgroundHex.Substring(5, 2), 16)
        $gfx.Clear([System.Drawing.Color]::FromArgb(255, $ri, $gi, $bi))
        $gfx.DrawImage($src, 0, 0, $src.Width, $src.Height)
        $tmp = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), '.png')
        $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
        return $tmp
    } finally {
        $gfx.Dispose(); $bmp.Dispose(); $src.Dispose()
    }
}

function Show-BuildWelcomeHero {
    Sync-Win11IsoSpectreConsoleDimension
    $cols = Get-Win11IsoTerminalWidth
    Write-Verbose "Splash layout: terminal ${cols} cols (assumed default $($script:Win11IsoAssumedTerminalCols) when RawUI missing)."
    $ruleAccent = [string]$script:Win11IsoSplashHeroRuleAccentColor
    if ([string]::IsNullOrWhiteSpace($ruleAccent)) { $ruleAccent = 'DodgerBlue1' }
    $ruleLine = [string]$script:Win11IsoSplashHeroRuleLineColor
    if ([string]::IsNullOrWhiteSpace($ruleLine)) { $ruleLine = 'Grey' }
    $dryLine = [string]$script:Win11IsoSplashHeroDryRunMarkup
    if ([string]::IsNullOrWhiteSpace($dryLine)) {
        $dryLine = '[dim grey70]-DryRun[/] [dodgerblue1]·[/] [dim grey70]read-only; no WIM mount, ISO write, disk prep, or USB.[/]'
    }
    $heroPngPath = Join-Path (Get-WinMintRepositoryRoot) 'assets\brand\WinMint.svg'
    $heroMaxW = [Math]::Max(32, [int]($cols * 0.75))
    Write-Verbose "Splash image: MaxWidth=$heroMaxW (terminal ${cols} cols)."
    $bgHex   = Get-TerminalBackgroundColor
    $tmpPng  = $null
    $renderPath = $heroPngPath
    if ($bgHex -and [IO.Path]::GetExtension($heroPngPath) -ieq '.png') {
        Write-Verbose "Terminal background: $bgHex — compositing hero PNG."
        $tmpPng     = New-Win11IsoCompositedPng -SourcePath $heroPngPath -BackgroundHex $bgHex
        $renderPath = $tmpPng
    }
    try {
        Get-SpectreImage -ImagePath $renderPath -MaxWidth $heroMaxW -Format Sixel | Out-SpectreHost
    }
    catch {
        Write-Verbose "Splash image render skipped: $($_.Exception.Message)"
        $rows = Get-Win11IsoTerminalHeight
        foreach ($line in @(Get-Win11IsoSplashHeroBanner -Cols $cols -Rows $rows -ShortTitle 'WinMint')) {
            if ($script:UseSpectre -and (Get-Command Write-SpectreHost -ErrorAction SilentlyContinue)) {
                $null = Write-SpectreHost "[dodgerblue1]$([Spectre.Console.Markup]::Escape($line))[/]"
            }
            else {
                Write-Host $line
            }
        }
    }
    finally {
        if ($tmpPng) { Remove-Item -LiteralPath $tmpPng -Force -ErrorAction SilentlyContinue }
    }
    Invoke-Win11IsoLogStreamFlushUnlessVerbose
    $null = Write-SpectreRule -Color $ruleAccent -LineColor $ruleLine
    $markupOverride = [string]$script:Win11IsoSplashRuleTitleMarkup
    if (-not [string]::IsNullOrWhiteSpace($markupOverride)) {
        $null = Write-SpectreHost $markupOverride.Trim()
    }
    if ($script:DryRun) {
        $null = Write-SpectreHost $dryLine
    }
}
$script:DismProgressCallback = $null
$script:PipelineTasks = $null
$script:PipelinePhaseStartedAt = @{}
$script:WinMintActionTimingVisibleThresholdSeconds = 60

function Format-WinMintDuration {
    param([Parameter(Mandatory)][TimeSpan]$Duration)

    if ($Duration.TotalHours -ge 1) {
        return ('{0}h {1}m {2}s' -f [int]$Duration.TotalHours, $Duration.Minutes, $Duration.Seconds)
    }
    if ($Duration.TotalMinutes -ge 1) {
        return ('{0}m {1}s' -f [int]$Duration.TotalMinutes, $Duration.Seconds)
    }
    if ($Duration.TotalSeconds -ge 1) {
        return ('{0:n1}s' -f $Duration.TotalSeconds)
    }
    return ('{0}ms' -f [int]$Duration.TotalMilliseconds)
}

function Format-WinMintByteSize {
    param([Parameter(Mandatory)][long]$Bytes)

    if ($Bytes -ge 1GB) { return ('{0:n2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:n1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:n1} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

# Get-Variable -ErrorAction SilentlyContinue is strict-mode-safe — direct
# $script:PipelineTasks access throws under StrictMode v2 when this file is
# dot-sourced into a ThreadJob scriptblock whose $script: scope diverges from
# where the variable was assigned. The Spectre console path sets the variable;
# the WPF UI ThreadJob path does not, and that's fine — these two functions
# become no-ops there.
function Start-PipelinePhase {
    param([string]$Name)
    if ($null -eq $script:PipelinePhaseStartedAt) { $script:PipelinePhaseStartedAt = @{} }
    $script:PipelinePhaseStartedAt[$Name] = [System.Diagnostics.Stopwatch]::StartNew()
    $handler = Get-Variable -Name WinMintProgressHandler -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $handler) {
        Write-WinMintProgress -Stage $Name -Level Section -Message "Starting $Name" -ProgressHandler $handler
    }
    $tasks = Get-Variable -Name PipelineTasks -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $tasks) { return }
    $task = $tasks[$Name]
    if ($null -eq $task) { return }
    $task.StartTask()
    $task.IsIndeterminate = $true
}

function Complete-PipelinePhase {
    param([string]$Name)
    $message = "Completed $Name"
    if ($null -ne $script:PipelinePhaseStartedAt -and $script:PipelinePhaseStartedAt.ContainsKey($Name)) {
        $timer = $script:PipelinePhaseStartedAt[$Name]
        $timer.Stop()
        $message = "$message in $(Format-WinMintDuration -Duration $timer.Elapsed)"
        $script:PipelinePhaseStartedAt.Remove($Name)
    }
    $handler = Get-Variable -Name WinMintProgressHandler -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $handler) {
        Write-WinMintProgress -Stage $Name -Level OK -Message $message -ProgressHandler $handler
    }
    $tasks = Get-Variable -Name PipelineTasks -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $tasks) { return }
    $task = $tasks[$Name]
    if ($null -eq $task) { return }
    $task.IsIndeterminate = $false
    $task.Value = 100
    $task.StopTask()
}

function Invoke-Action {
    <#
    <summary>
    Full build: log a clear step then run. Dry run: log the same step without
    side effects.
    </summary>
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [switch]$SpectreProgressIndeterminate
    )
    if ($script:DryRun) { LogDry $Description }
    else {
        Log $Description
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $completed = $false
        $useLiveProgress = $SpectreProgressIndeterminate -and
            -not (Test-Win11IsoVerboseLogging) -and
            -not [Console]::IsOutputRedirected -and
            (Get-Command Invoke-SpectreCommandWithProgress -ErrorAction SilentlyContinue)
        try {
            if ($useLiveProgress) {
                Invoke-SpectreCommandWithProgress -ScriptBlock {
                    param([Spectre.Console.ProgressContext]$Context)
                    $task = $Context.AddTask($Description)
                    $task.IsIndeterminate = $true
                    $script:DismProgressCallback = {
                        param([double]$Pct)
                        $task.IsIndeterminate = $false
                        $task.Value = $Pct
                    }.GetNewClosure()
                    try {
                        & $ScriptBlock
                    }
                    finally {
                        $task.Value = 100
                        $script:DismProgressCallback = $null
                    }
                }
            }
            else {
                & $ScriptBlock
            }
            $completed = $true
        }
        finally {
            $timer.Stop()
            if ($completed) {
                $elapsed = Format-WinMintDuration -Duration $timer.Elapsed
                $threshold = [double]$script:WinMintActionTimingVisibleThresholdSeconds
                if ($timer.Elapsed.TotalSeconds -ge $threshold) {
                    LogOK "$Description finished in $elapsed."
                } else {
                    LogVerbose "$Description finished in $elapsed."
                }
            }
            Invoke-Win11IsoLogStreamFlushUnlessVerbose
        }
    }
}
