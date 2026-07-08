#Requires -Version 7.6

[CmdletBinding()]
param(
    [ValidateSet('Success', 'Warnings', 'Failure', 'LongRun')]
    [string]$Scenario = 'Success',

    [string]$ProfilePath = '',

    [switch]$UseWindowsTerminal,

    [switch]$ForceSixel,

    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'

function Resolve-DemoRepoRoot {
    $toolsDir = Split-Path -Parent $PSScriptRoot
    return Split-Path -Parent $toolsDir
}

function Resolve-DemoProfilePath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return Join-Path $Root 'tests\profiles\hyper-v-install-arm64.json'
    }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return Join-Path $Root $Path
}

function Initialize-DemoUtf8Console {
    try {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $script:OutputEncoding = $utf8NoBom
        [Console]::InputEncoding = $utf8NoBom
        [Console]::OutputEncoding = $utf8NoBom
        $null = & chcp.com 65001 2>$null
    }
    catch { }
}

function Get-DemoPropertyValue {
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Get-DemoStringArray {
    param($Value)

    $items = @()
    foreach ($item in @($Value)) {
        $text = [string]$item
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $items += $text
        }
    }
    return $items
}

function Start-DemoInWindowsTerminal {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$ResolvedProfilePath,
        [Parameter(Mandatory)][string]$ScenarioName,
        [bool]$RenderSixel,
        [bool]$SuppressPause
    )

    if (-not [string]::IsNullOrWhiteSpace($env:WT_SESSION)) { return $false }

    $terminalCommand = Get-Command wt.exe -ErrorAction SilentlyContinue
    $terminalPath = if ($terminalCommand) { $terminalCommand.Source } else { '' }
    if ([string]::IsNullOrWhiteSpace($terminalPath)) {
        $candidate = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $terminalPath = $candidate
        }
    }
    if ([string]::IsNullOrWhiteSpace($terminalPath)) {
        Write-Warning 'Windows Terminal was requested, but wt.exe was not found. Continuing in the current console.'
        return $false
    }

    $arguments = @(
        'new-tab',
        '--title',
        'WinMint FirstLogon Demo',
        'pwsh',
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $ScriptPath,
        '-Scenario',
        $ScenarioName,
        '-ProfilePath',
        $ResolvedProfilePath
    )
    if ($RenderSixel) { $arguments += '-ForceSixel' }
    if ($SuppressPause) { $arguments += '-NoPause' }

    Start-Process -FilePath $terminalPath -ArgumentList $arguments -WindowStyle Normal
    return $true
}

function New-DemoAgentProfile {
    param($BuildProfile)

    $source = Get-DemoPropertyValue -Object $BuildProfile -Name 'source'
    $desktop = Get-DemoPropertyValue -Object $BuildProfile -Name 'desktop'
    $development = Get-DemoPropertyValue -Object $BuildProfile -Name 'development'
    $features = Get-DemoPropertyValue -Object $BuildProfile -Name 'features'
    $wsl = Get-DemoPropertyValue -Object $development -Name 'wsl'

    $layers = Get-DemoStringArray -Value (Get-DemoPropertyValue -Object $desktop -Name 'layers' -Default @())
    $browsers = Get-DemoStringArray -Value (Get-DemoPropertyValue -Object $development -Name 'browsers' -Default @())
    $editors = Get-DemoStringArray -Value (Get-DemoPropertyValue -Object $development -Name 'editors' -Default @())
    $distros = Get-DemoStringArray -Value (Get-DemoPropertyValue -Object $wsl -Name 'distros' -Default @())
    $architecture = [string](Get-DemoPropertyValue -Object $source -Name 'architecture' -Default 'arm64')
    $launcher = [string](Get-DemoPropertyValue -Object $features -Name 'launcher' -Default 'None')

    $usesNilesoft = $layers -contains 'nilesoft'
    $usesYasb = $layers -contains 'yasb'
    $usesKomorebi = $layers -contains 'komorebi'
    $usesWindhawk = $layers -contains 'windhawk'

    return [pscustomobject]@{
        targetArchitecture = $architecture
        browsers = $browsers
        editors = $editors
        modules = [pscustomobject]@{
            packageManagers = [pscustomobject]@{ enabled = $true }
            wsl = [pscustomobject]@{
                enabled = $true
                distros = $distros
            }
            shell = [pscustomobject]@{
                enabled = [bool]($usesNilesoft -or $usesYasb -or $usesKomorebi)
                nilesoft = $usesNilesoft
                yasb = $usesYasb
                komorebi = $usesKomorebi
                whkd = $usesKomorebi
            }
            windhawk = [pscustomobject]@{ enabled = $usesWindhawk }
            raycast = [pscustomobject]@{ enabled = ($launcher -eq 'Raycast') }
            launcherKey = [pscustomobject]@{
                enabled = $true
                target = $(if ($launcher -eq 'Raycast') { 'Raycast' } else { 'Search' })
                chord = 'Win+Shift+F23'
            }
        }
    }
}

function Write-DemoState {
    $script:demoState | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $script:statePath -Encoding utf8
}

function Start-DemoDelay {
    param([int]$Milliseconds = 250)
    if ($NoPause) { return }
    Start-Sleep -Milliseconds $Milliseconds
}

function Write-DemoStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('running', 'ok', 'failed', 'skipped', 'retryable', 'needsReboot')]
        [string]$Status,
        [Parameter(Mandatory)][string]$Message,
        [int]$DelayMilliseconds = 250
    )

    $script:demoState.steps[$Name] = [ordered]@{
        status = $Status
        message = $Message
        updatedAt = Get-Date -Format o
    }
    Write-DemoState
    Write-AgentEvent -Type 'step' -Status $Status -Step $Name -Message $Message -Data @{ demo = $true; scenario = $Scenario }

    $level = switch ($Status) {
        'ok' { 'OK' }
        'failed' { 'Error' }
        'retryable' { 'Warn' }
        'needsReboot' { 'Warn' }
        'skipped' { 'Warn' }
        default { 'Info' }
    }
    $displayName = switch ($Name) {
        'package-managers' { 'Package managers' }
        'winget-upgrade' { 'App updates' }
        'browsers' { 'Browsers' }
        'editors' { 'Editors' }
        'wsl' { 'WSL' }
        'desktop-shell' { 'Desktop shell' }
        'cleanup' { 'Cleanup' }
        default { $Name }
    }
    Write-AgentConsoleLine -Level $level -Message "$displayName - $Message"
    Start-DemoDelay -Milliseconds $DelayMilliseconds
}

function New-DemoCommandLog {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Lines
    )

    $fileName = $Name -replace '[^A-Za-z0-9_.-]', '-'
    $path = Join-Path $script:commandLogDir "$fileName.log"
    $Lines | Out-File -LiteralPath $path -Encoding utf8
    return $path
}

function ConvertTo-DemoDisplayPath {
    param([Parameter(Mandatory)][string]$Path)

    $tempPrefix = [System.IO.Path]::GetTempPath().TrimEnd('\', '/')
    if ($Path.StartsWith($tempPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $suffix = $Path.Substring($tempPrefix.Length).TrimStart('\', '/')
        return Join-Path '%TEMP%' $suffix
    }
    return $Path
}

function Show-DemoRunOverview {
    $runName = Split-Path -Leaf $script:stateDir
    $profileName = [string](Get-DemoPropertyValue -Object $script:buildProfile -Name 'profileName' -Default 'BuildProfile')
    $logRoot = ConvertTo-DemoDisplayPath -Path $script:logDir
    if ($script:AgentConsoleReady) {
        $safeScenario = Get-AgentEscapedText -Text $Scenario
        $safeProfileName = Get-AgentEscapedText -Text $profileName
        $safeRunName = Get-AgentEscapedText -Text $runName
        $safeLogRoot = Get-AgentEscapedText -Text $logRoot
        $profileBody = @(
            "[grey]Scenario[/]  [white]$safeScenario[/]"
            "[grey]Profile [/][white]$safeProfileName[/]"
            "[grey]Run     [/][silver]$safeRunName[/]"
        ) -join "`n"
        $modeBody = @(
            '[grey]Preview only[/]'
            '[white]No installers, registry writes, WSL changes, or RunOnce changes.[/]'
            ''
            "[grey]Logs[/] [silver]$safeLogRoot[/]"
        ) -join "`n"
        $profilePanel = New-AgentSpectrePanel -Data $profileBody -Header '[bold white]Demo profile[/]' -Color Grey
        $modePanel = New-AgentSpectrePanel -Data $modeBody -Header '[bold white]Mode[/]' -Color Grey
        if ((Get-AgentConsoleWidth) -ge 104 -and (Get-Command Format-SpectreColumns -ErrorAction SilentlyContinue)) {
            @($profilePanel, $modePanel) | Format-SpectreColumns -Padding 2 -Expand | Out-AgentSpectreRenderable
        }
        elseif (Get-Command Format-SpectreRows -ErrorAction SilentlyContinue) {
            @($profilePanel, $modePanel) | Format-SpectreRows | Out-AgentSpectreRenderable
        }
        else {
            $profilePanel | Out-AgentSpectreRenderable
            $modePanel | Out-AgentSpectreRenderable
        }
        Write-Host ''
        return
    }
    $lines = @(
        'Preview only. No installers, registry writes, WSL changes, or RunOnce changes.'
        "Scenario: $Scenario"
        "Profile:  $profileName"
        "Run:      $runName"
        "Logs:     $logRoot"
    )
    $lines | ForEach-Object { Write-Host $_ }
}

function Show-DemoArtifacts {
    param([Parameter(Mandatory)][string]$SummaryPath)

    $root = ConvertTo-DemoDisplayPath -Path $script:stateDir
    if ($script:AgentConsoleReady) {
        $safeRoot = Get-AgentEscapedText -Text $root
        $body = @(
            "[grey]Root   [/][silver]$safeRoot[/]"
            '[grey]Events [/][silver]Logs\WinMintAgent-events.jsonl[/]'
            '[grey]Summary[/][silver]Logs\WinMintFirstLogonDemo-summary.txt[/]'
        ) -join "`n"
        New-AgentSpectrePanel -Data $body -Header '[bold white]Demo files[/]' -Color Grey -Expand |
            Out-AgentSpectreRenderable
        Write-Host ''
        return
    }
    Write-Host "Root: $root"
    Write-Host 'Events: Logs\WinMintAgent-events.jsonl'
    Write-Host 'Summary: Logs\WinMintFirstLogonDemo-summary.txt'
}

function Invoke-DemoScenario {
    Write-AgentEvent -Type 'demo' -Status 'running' -Message 'WinMint FirstLogon visual demo started.' -Data @{ scenario = $Scenario }
    Show-AgentConsoleHeader
    Show-DemoRunOverview
    Show-AgentPlan

    if ($script:AgentConsoleReady) {
        $body = '[grey]First-logon actions are simulated below. Each step writes state and structured events.[/]'
        New-AgentSpectrePanel -Data $body -Header '[bold white]Progress[/]' -Color DodgerBlue1 -Expand |
            Out-AgentSpectreRenderable
    }

    Write-DemoStep -Name 'package-managers' -Status 'running' -Message 'checking package sources'
    Write-DemoStep -Name 'package-managers' -Status 'ok' -Message 'ready'

    Write-DemoStep -Name 'winget-upgrade' -Status 'running' -Message 'previewing winget upgrade --all'
    $null = New-DemoCommandLog -Name '01-winget-upgrade' -Lines @(
        'DEMO ONLY - command not executed',
        'winget upgrade --all --accept-package-agreements --accept-source-agreements',
        'Sample result: Windows Terminal, App Installer, and Store apps are current.'
    )

    if ($Scenario -eq 'Warnings') {
        Write-DemoStep -Name 'winget-upgrade' -Status 'retryable' -Message 'Store source returned a transient warning; logs captured.'
    }
    else {
        Write-DemoStep -Name 'winget-upgrade' -Status 'ok' -Message 'current'
    }

    Write-DemoStep -Name 'browsers' -Status 'running' -Message 'installing selected browsers'
    $null = New-DemoCommandLog -Name '02-browser-installs' -Lines @(
        'DEMO ONLY - installers not executed',
        'Selected browsers: ' + (@((Get-WinMintAgentContext).AgentProfile.browsers) -join ', '),
        'Desktop shortcuts: cleanup would remove installer-created .lnk files.'
    )
    if ($Scenario -eq 'Failure') {
        Write-DemoStep -Name 'browsers' -Status 'failed' -Message 'Helium installer failed in the preview scenario.'
    }
    else {
        Write-DemoStep -Name 'browsers' -Status 'ok' -Message 'installed; shortcuts cleaned'
    }

    Write-DemoStep -Name 'editors' -Status 'running' -Message 'preparing selected editors'
    Write-DemoStep -Name 'editors' -Status 'ok' -Message 'ready'

    Write-DemoStep -Name 'wsl' -Status 'running' -Message 'updating runtime'
    if ($Scenario -eq 'LongRun') {
        Write-DemoStep -Name 'wsl' -Status 'running' -Message 'downloading runtime package' -DelayMilliseconds 900
        Write-DemoStep -Name 'wsl' -Status 'running' -Message 'registering distro metadata' -DelayMilliseconds 900
    }
    if ($Scenario -eq 'Warnings') {
        Write-DemoStep -Name 'wsl' -Status 'needsReboot' -Message 'WSL runtime requested a reboot before distro first launch.'
    }
    else {
        Write-DemoStep -Name 'wsl' -Status 'ok' -Message 'distros prepared'
    }

    Write-DemoStep -Name 'desktop-shell' -Status 'running' -Message 'applying shell layers'
    Write-DemoStep -Name 'desktop-shell' -Status 'ok' -Message 'terminal profiles finalized'

    if ($Scenario -eq 'Failure') {
        Write-DemoStep -Name 'cleanup' -Status 'skipped' -Message 'Final cleanup skipped because a blocking step failed.'
    }
    else {
        Write-DemoStep -Name 'cleanup' -Status 'ok' -Message 'bare-metal cleanup complete'
    }

    $script:demoState.completedAt = Get-Date -Format o
    Write-DemoState

    Show-AgentFinalSummary -State $script:demoState

    $failed = @($script:demoState.steps.Values | Where-Object { $_.status -eq 'failed' }).Count -gt 0
    $warnings = @($script:demoState.steps.Values | Where-Object { $_.status -in @('retryable', 'needsReboot') }).Count -gt 0
    $finalStatus = if ($failed) { 'failed' } elseif ($warnings) { 'warning' } else { 'ok' }
    Write-AgentEvent -Type 'demo' -Status $finalStatus -Message 'WinMint FirstLogon visual demo completed.' -Data @{ scenario = $Scenario }

    $summaryPath = Join-Path $script:logDir 'WinMintFirstLogonDemo-summary.txt'
    @(
        "Scenario: $Scenario",
        "Profile: $script:profileDisplayPath",
        "State: $script:statePath",
        "Events: $script:eventLogPath",
        "Command logs: $script:commandLogDir",
        "Exit behavior: demo rendering exits 0 even when the Failure scenario displays a failed step."
    ) | Out-File -LiteralPath $summaryPath -Encoding utf8

    Show-DemoArtifacts -SummaryPath $summaryPath

    if ($failed) {
        Write-AgentConsoleLine -Level Error -Message 'Failure scenario rendered. The demo still exits 0 for visual iteration.'
    }
    elseif ($warnings) {
        Write-AgentConsoleLine -Level Warn -Message 'Warning scenario rendered. Review the event log to see warning states.'
    }
    else {
        Write-AgentConsoleLine -Level OK -Message 'Success scenario rendered.'
    }

    if (-not $NoPause) {
        $null = Read-Host 'Press Enter to close the demo'
    }
}

$repoRoot = Resolve-DemoRepoRoot
$resolvedProfilePath = Resolve-DemoProfilePath -Root $repoRoot -Path $ProfilePath
$forceSixelForDemo = [bool]($ForceSixel -or $UseWindowsTerminal -or -not [string]::IsNullOrWhiteSpace($env:WT_SESSION))
if ($UseWindowsTerminal) {
    $started = Start-DemoInWindowsTerminal -ScriptPath $PSCommandPath -ResolvedProfilePath $resolvedProfilePath -ScenarioName $Scenario -RenderSixel $forceSixelForDemo -SuppressPause ([bool]$NoPause)
    if ($started) { exit 0 }
}

Initialize-DemoUtf8Console

if (-not (Test-Path -LiteralPath $resolvedProfilePath -PathType Leaf)) {
    throw "Profile not found: $resolvedProfilePath"
}

$script:profileDisplayPath = $resolvedProfilePath
$script:buildProfile = Get-Content -LiteralPath $resolvedProfilePath -Raw | ConvertFrom-Json
$agentProfile = New-DemoAgentProfile -BuildProfile $script:buildProfile
$agentRoot = Join-Path $repoRoot 'src\runtime\firstlogon'

$tempRoot = [System.IO.Path]::GetTempPath().TrimEnd('\', '/')
$demoRunId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
$script:stateDir = Join-Path $tempRoot ('WinMintFirstLogonDemo-' + $demoRunId)
$script:logDir = Join-Path $script:stateDir 'Logs'
$script:commandLogDir = Join-Path $script:logDir 'Commands'
$script:statePath = Join-Path $script:stateDir 'state.json'
$script:eventLogPath = Join-Path $script:logDir 'WinMintAgent-events.jsonl'
$script:AgentConsoleReady = $false
$script:AgentConsoleLogLabel = 'demo sandbox in %TEMP% (details below)'
$script:AgentConsoleSplashImagePath = Join-Path $repoRoot 'assets\brand\winmint_hero.png'
$script:AgentConsoleForceSixel = $forceSixelForDemo
$script:AgentConsoleSplashMaxWidth = 52
$script:AgentCommandCounter = 0

$null = New-Item -ItemType Directory -Path $script:logDir -Force
$null = New-Item -ItemType Directory -Path $script:commandLogDir -Force

$script:demoState = [ordered]@{
    schemaVersion = 1
    demo = $true
    scenario = $Scenario
    startedAt = Get-Date -Format o
    completedAt = $null
    profilePath = $resolvedProfilePath
    steps = [ordered]@{}
}
Write-DemoState

. (Join-Path $agentRoot 'Agent.Context.ps1')
Set-WinMintAgentContext -Context (New-WinMintAgentContext @{
        AgentRoot = $agentRoot
        State = $script:demoState
        StatePath = $script:statePath
        AgentProfile = $agentProfile
        LogDir = $script:logDir
        EventLogPath = $script:eventLogPath
        CommandLogDir = $script:commandLogDir
        StateDir = $script:stateDir
        TargetArchitecture = [string]$agentProfile.targetArchitecture
        Interactive = $true
        EmitProgressJson = $false
    })
. (Join-Path $agentRoot 'Agent.Plan.ps1')
. (Join-Path $agentRoot 'Agent.Console.ps1')

Initialize-AgentConsole
Invoke-DemoScenario
exit 0

