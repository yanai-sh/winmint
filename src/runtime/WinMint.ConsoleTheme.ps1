#Requires -Version 7.6
<#
.SYNOPSIS
  Shared One Half Dark console theme for engine Logging and FirstLogon Agent.
  Markup helpers only — no file sinks, no Log* API.
#>

# https://github.com/sonph/onehalf — matches Windows Terminal "One Half Dark".
$script:WinMintConsoleTheme = @{
    Bg         = '#282c34'
    Fg         = '#dcdfe4'
    FgMuted    = '#abb2bf'
    FgDim      = '#5c6370'
    Gutter     = '#3e4452'
    Blue       = '#61afef'
    Cyan       = '#56b6c2'
    Green      = '#98c379'
    Yellow     = '#e5c07b'
    Red        = '#e06c75'
    Orange     = '#d19a66'
    Purple     = '#c678dd'
    White      = '#dcdfe4'
}
$script:WinMintConsoleAccentColor = $script:WinMintConsoleTheme.Blue
$script:WinMintConsoleRuleLineColor = $script:WinMintConsoleTheme.Gutter

function Get-WinMintConsoleTheme {
    param([Parameter(Mandatory)][string]$Name)
    $t = $script:WinMintConsoleTheme
    if ($t -is [hashtable] -and $t.ContainsKey($Name)) { return [string]$t[$Name] }
    return '#abb2bf'
}

function Get-WinMintConsoleAccentColor {
    if ($script:WinMintConsoleAccentColor) { return [string]$script:WinMintConsoleAccentColor }
    return (Get-WinMintConsoleTheme Blue)
}

function Get-WinMintConsoleRuleLineColor {
    if ($script:WinMintConsoleRuleLineColor) { return [string]$script:WinMintConsoleRuleLineColor }
    return (Get-WinMintConsoleTheme Gutter)
}

function New-WinMintConsoleBadgeMarkup {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$AccentHex
    )
    $bg = Get-WinMintConsoleTheme Bg
    return "[bold $bg on $AccentHex]$Label[/]"
}

function Initialize-WinMintConsoleLevelStyles {
    $script:WinMintConsoleLevelStyles = @{
        INFO    = @{
            Badge = ' RUN '; Plain = '●'
            BadgeMarkup = (New-WinMintConsoleBadgeMarkup -Label ' RUN ' -AccentHex (Get-WinMintConsoleTheme Blue))
            MessageColor = (Get-WinMintConsoleTheme Fg); Rail = (Get-WinMintConsoleTheme Blue)
        }
        OK      = @{
            Badge = '  OK '; Plain = '✓'
            BadgeMarkup = (New-WinMintConsoleBadgeMarkup -Label '  OK ' -AccentHex (Get-WinMintConsoleTheme Green))
            MessageColor = (Get-WinMintConsoleTheme FgMuted); Rail = (Get-WinMintConsoleTheme Green)
        }
        WARN    = @{
            Badge = 'WARN '; Plain = '!'
            BadgeMarkup = (New-WinMintConsoleBadgeMarkup -Label ' WARN ' -AccentHex (Get-WinMintConsoleTheme Yellow))
            MessageColor = (Get-WinMintConsoleTheme Yellow); Rail = (Get-WinMintConsoleTheme Yellow)
        }
        ERROR   = @{
            Badge = ' ERR '; Plain = '✕'
            BadgeMarkup = (New-WinMintConsoleBadgeMarkup -Label ' ERR ' -AccentHex (Get-WinMintConsoleTheme Red))
            MessageColor = (Get-WinMintConsoleTheme Red); Rail = (Get-WinMintConsoleTheme Red)
        }
        DRY     = @{
            Badge = ' DRY '; Plain = '◇'
            BadgeMarkup = (New-WinMintConsoleBadgeMarkup -Label ' DRY ' -AccentHex (Get-WinMintConsoleTheme Orange))
            MessageColor = (Get-WinMintConsoleTheme FgMuted); Rail = (Get-WinMintConsoleTheme Orange)
        }
        SECTION = @{
            Badge = ' ◆  '; Plain = '◆'
            BadgeMarkup = "[bold $(Get-WinMintConsoleTheme Cyan)]◆[/]"
            MessageColor = (Get-WinMintConsoleTheme Cyan); Rail = (Get-WinMintConsoleTheme Cyan)
        }
        VERBOSE = @{
            Badge = ' ·  '; Plain = '·'
            BadgeMarkup = "[dim $(Get-WinMintConsoleTheme FgDim)]·[/]"
            MessageColor = (Get-WinMintConsoleTheme FgDim); Rail = (Get-WinMintConsoleTheme Gutter)
        }
    }
}

function Get-WinMintConsoleLevelStyle {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'DRY', 'SECTION', 'VERBOSE')]
        [string]$Level
    )
    if (-not $script:WinMintConsoleLevelStyles) { Initialize-WinMintConsoleLevelStyles }
    $table = $script:WinMintConsoleLevelStyles
    if ($table -is [hashtable] -and $table.ContainsKey($Level)) { return $table[$Level] }
    return @{
        Badge = " $Level "; BadgeMarkup = "[bold]$Level[/]"; Plain = '·'
        MessageColor = (Get-WinMintConsoleTheme Fg); Rail = (Get-WinMintConsoleTheme Gutter)
    }
}

function Format-WinMintConsoleLineMarkup {
    <#
    .SYNOPSIS
      Shared log line: rail · clock · badge · message. Pass -SafeMessage when already escaped for Spectre.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'DRY', 'SECTION', 'VERBOSE')]
        [string]$Level,
        [Parameter(Mandatory)][string]$Message,
        [string]$SafeMessage = ''
    )
    $style = Get-WinMintConsoleLevelStyle -Level $Level
    $safe = if (-not [string]::IsNullOrEmpty($SafeMessage)) {
        $SafeMessage
    }
    else {
        ($Message -replace '\[', '[[')
    }
    $rail = [string]$style.Rail
    if ([string]::IsNullOrWhiteSpace($rail)) { $rail = Get-WinMintConsoleTheme Gutter }
    $dim = Get-WinMintConsoleTheme FgDim
    $ts = "[$dim]$((Get-Date).ToString('HH:mm:ss'))[/]"
    return "[$rail]│[/] $ts  $([string]$style.BadgeMarkup)  [$([string]$style.MessageColor)]$safe[/]"
}

function Format-WinMintConsolePlainGlyph {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'DRY', 'SECTION', 'VERBOSE')]
        [string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    $style = Get-WinMintConsoleLevelStyle -Level $Level
    return "$([string]$style.Plain) $Message"
}

Initialize-WinMintConsoleLevelStyles
