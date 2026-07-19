#Requires -Version 7.6
<#
.SYNOPSIS
    Start/taskbar pin selection policy and Windows Terminal hard-replace contracts.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-PinTerminalFailure {
    param([string]$Message)
    $script:failures.Add($Message) | Out-Null
}

. (Join-Path $root 'src\runtime\setup\FirstLogon.Desktop.ps1')
. (Join-Path $root 'src\runtime\setup\WindowsTerminal.Profiles.ps1')

# --- Pin selection (Edge pins only when development.browsers contains edge) ---
$withZen = Get-WinMintFirstLogonPinSelection -Browsers @('zen-browser') -Editors @('cursor', 'neovim')
if ($withZen.PinEdgeToStart -or $withZen.PinEdgeToTaskbar) { Add-PinTerminalFailure 'zen-only browsers must not pin Edge.' }
if ($withZen.StartAppIds -contains 'edge') { Add-PinTerminalFailure 'StartAppIds must exclude edge when browsers omit edge.' }
if ($withZen.StartAppIds -notcontains 'zen-browser') { Add-PinTerminalFailure 'StartAppIds must include zen-browser.' }
if ($withZen.StartAppIds -notcontains 'cursor') { Add-PinTerminalFailure 'StartAppIds must include cursor.' }
if ($withZen.StartAppIds -contains 'neovim') { Add-PinTerminalFailure 'neovim is CLI-only and must not be pinned.' }
if ($withZen.TaskbarAppIds -notcontains 'zen-browser' -or $withZen.TaskbarAppIds -notcontains 'cursor') {
    Add-PinTerminalFailure 'TaskbarAppIds must include selected browser and editor.'
}

$edgeOnly = Get-WinMintFirstLogonPinSelection -Browsers @('edge') -Editors @('vscode')
if ($edgeOnly.PinEdgeToStart -ne $true) { Add-PinTerminalFailure 'browsers=edge must pin Edge to Start.' }
if ($edgeOnly.PinEdgeToTaskbar -ne $true) { Add-PinTerminalFailure 'sole browser edge must pin Edge to taskbar.' }
if ($edgeOnly.TaskbarAppIds -notcontains 'edge') { Add-PinTerminalFailure 'Sole-browser Edge must appear in TaskbarAppIds.' }

$edgeWithBrave = Get-WinMintFirstLogonPinSelection -Browsers @('brave', 'edge') -Editors @()
if ($edgeWithBrave.PinEdgeToStart -ne $true) { Add-PinTerminalFailure 'browsers including edge must pin Edge to Start.' }
if ($edgeWithBrave.PinEdgeToTaskbar) { Add-PinTerminalFailure 'edge + another browser must NOT pin Edge to taskbar.' }

$noEdge = Get-WinMintFirstLogonPinSelection -Browsers @('brave') -Editors @()
if ($noEdge.PinEdgeToStart -or $noEdge.PinEdgeToTaskbar) { Add-PinTerminalFailure 'browsers without edge must not pin Edge.' }

$desktopText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\FirstLogon.Desktop.ps1') -Raw
foreach ($expected in @('applied', 'skipped', 'appliedAfterAgent', 'underProvisioningLock', 'FirstLogon_ShellPins.json')) {
    if ($desktopText -notmatch [regex]::Escape($expected)) {
        Add-PinTerminalFailure "Set-WinMintFirstLogonStartPins report must include '$expected'."
    }
}
$runtimeText = Get-Content -LiteralPath (Join-Path $root 'src\runtime\setup\FirstLogon.Runtime.ps1') -Raw
if ($runtimeText -notmatch "finalize-desktop-under-lock[\s\S]*Set-WinMintFirstLogonStartPins") {
    Add-PinTerminalFailure 'Pins must apply in finalize-desktop-under-lock (after agent, under lock).'
}
if ($runtimeText -notmatch "finalize-success[\s\S]*Invoke-WinMintFirstLogonReloadExplorerShell") {
    Add-PinTerminalFailure 'Explorer reload for pins must run on finalize-success (after lock release path).'
}

# --- Terminal hard-replace ---
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("winmint-term-" + [guid]::NewGuid().ToString('n'))
$settingsDir = Join-Path $tempRoot 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
$null = New-Item -ItemType Directory -Path $settingsDir -Force
$settingsPath = Join-Path $settingsDir 'settings.json'
@{
    profiles = @{
        defaults = @{}
        list     = @(
            @{ name = 'Command Prompt'; guid = '{0caa0dad-35be-5f56-a8ff-afceeeaa6101}' }
            @{ name = 'Windows PowerShell'; source = 'Windows.Terminal.WindowsPowerShell' }
            @{ name = 'Ubuntu'; source = 'Windows.Terminal.Wsl'; commandline = 'wsl.exe -d Ubuntu' }
        )
    }
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $settingsPath -Encoding UTF8

$prevLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = $tempRoot
    $status = Set-WinMintWindowsTerminalProfiles -WslDistros @('FedoraLinux') -MockWslProfiles
    if ($status -ne 'updated-with-wsl-mock') {
        Add-PinTerminalFailure "Expected updated-with-wsl-mock, got '$status'."
    }
    $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $names = @($settings.profiles.list | ForEach-Object { [string]$_.name })
    if ($names.Count -ne 2) {
        Add-PinTerminalFailure "Hard-replace must leave exactly 2 profiles, got $($names.Count): $($names -join ', ')"
    }
    if ($names[0] -ne 'PowerShell' -or $names[1] -ne 'Fedora') {
        Add-PinTerminalFailure "Expected PowerShell then Fedora, got: $($names -join ', ')"
    }
    if ([string]$settings.launchMode -ne 'default') {
        Add-PinTerminalFailure "launchMode must be default, got '$($settings.launchMode)'."
    }
    if (-not [bool]$settings.centerOnLaunch) {
        Add-PinTerminalFailure 'centerOnLaunch must be true.'
    }
    if ([int]$settings.profiles.defaults.opacity -ne 80) {
        Add-PinTerminalFailure "opacity must be 80, got '$($settings.profiles.defaults.opacity)'."
    }
    if ([string]$settings.profiles.defaults.colorScheme -ne 'One Half Dark') {
        Add-PinTerminalFailure 'colorScheme must be One Half Dark.'
    }
    if ($names -contains 'Command Prompt' -or $names -contains 'Windows PowerShell' -or $names -contains 'Ubuntu') {
        Add-PinTerminalFailure 'Hard-replace must strip stock leftover profiles.'
    }
}
finally {
    $env:LOCALAPPDATA = $prevLocalAppData
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Seed asset parity ---
$seed = Get-Content -LiteralPath (Join-Path $root 'assets\runtime\windows-terminal\settings.json') -Raw | ConvertFrom-Json
if ([string]$seed.launchMode -ne 'default') {
    Add-PinTerminalFailure "Seed settings.json launchMode must be default (was '$($seed.launchMode)')."
}
if ([int]$seed.profiles.defaults.opacity -ne 80) {
    Add-PinTerminalFailure "Seed settings.json opacity must be 80 (was '$($seed.profiles.defaults.opacity)')."
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}

Write-Host 'Shell pins + Terminal profiles contract: OK'
exit 0
