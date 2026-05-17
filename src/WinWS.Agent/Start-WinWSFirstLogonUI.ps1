#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Continue'
$script:AgentExitCode = 0

# ── STA guard ─────────────────────────────────────────────────────────────────
# WPF requires STA. Windows PowerShell (5.1) is STA by default; PS7 is not.
# Re-launch via powershell.exe -STA if needed.
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
    $ps5 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $ps5)) {
        Write-Warning 'STA thread required for WPF but powershell.exe was not found. Falling back to console agent.'
        exit 2
    }
    $fwdArgs = @('-STA', '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Force) { $fwdArgs += '-Force' }
    $proc = Start-Process -FilePath $ps5 -ArgumentList $fwdArgs -Wait -PassThru -WindowStyle Hidden
    exit ([int]$proc.ExitCode)
}

# ── Paths ─────────────────────────────────────────────────────────────────────
$agentRoot  = Split-Path -Parent $PSCommandPath
$stateDir   = Join-Path $env:LOCALAPPDATA 'WinWS'
$statePath  = Join-Path $stateDir 'state.json'

$profilePath = Join-Path $agentRoot 'BuildProfile.json'

# ── Load agent profile ────────────────────────────────────────────────────────
function Read-UIJson {
    param([string]$Path)
    try {
        if (Test-Path -LiteralPath $Path) {
            return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    } catch { }
    return $null
}

function Get-UIObjectProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Fallback = $null
    )
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) {
        return $Object.PSObject.Properties[$Name].Value
    }
    return $Fallback
}

function ConvertTo-UIStringArray {
    param([object]$Value)
    $items = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @($Value)) {
        if ($null -eq $entry) { continue }
        foreach ($part in ([string]$entry -split ',')) {
            $text = $part.Trim()
            if (-not [string]::IsNullOrWhiteSpace($text) -and $text -ne 'None') {
                $items.Add($text) | Out-Null
            }
        }
    }
    return @($items | Select-Object -Unique)
}

function ConvertTo-UILoadoutLabel {
    param([string]$Value)
    switch ($Value) {
        'cursor'      { return 'Cursor' }
        'vscodium'    { return 'VSCodium' }
        'neovim'      { return 'Neovim' }
        'zed'         { return 'Zed' }
        'windhawk'    { return 'Windhawk' }
        'yasb'        { return 'YASB' }
        'komorebi'    { return 'Komorebi' }
        'whkd'        { return 'whkd' }
        'standard'    { return 'Standard Windows' }
        'Ubuntu'      { return 'Ubuntu' }
        'FedoraLinux' { return 'Fedora Linux' }
        default {
            if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
            return [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ToTitleCase(([string]$Value -replace '[-_]', ' '))
        }
    }
}

function Get-UILoadoutSummary {
    param([object]$BuildProfile)

    $profileName = [string](Get-UIObjectProperty -Object $BuildProfile -Name 'profileName' -Fallback (Get-UIObjectProperty -Object $BuildProfile -Name 'profile' -Fallback 'Developer'))
    $development = Get-UIObjectProperty -Object $BuildProfile -Name 'development'
    $modules = Get-UIObjectProperty -Object $BuildProfile -Name 'modules'
    $desktop = Get-UIObjectProperty -Object $BuildProfile -Name 'desktop'

    $editorSource = Get-UIObjectProperty -Object $BuildProfile -Name 'editors'
    if ($development) {
        $editorSource = Get-UIObjectProperty -Object $development -Name 'editors' -Fallback $editorSource
    }
    $editors = @(ConvertTo-UIStringArray -Value $editorSource | ForEach-Object { ConvertTo-UILoadoutLabel -Value $_ })

    $wslSource = $null
    if ($modules) {
        $wslModule = Get-UIObjectProperty -Object $modules -Name 'wsl'
        if ($wslModule) {
            $wslSource = Get-UIObjectProperty -Object $wslModule -Name 'distros' -Fallback (Get-UIObjectProperty -Object $wslModule -Name 'distro')
        }
    }
    if ($development) {
        $wslDev = Get-UIObjectProperty -Object $development -Name 'wsl'
        if ($wslDev) {
            $wslSource = Get-UIObjectProperty -Object $wslDev -Name 'distros' -Fallback $wslSource
        }
    }
    if (-not $wslSource) {
        $wslSource = Get-UIObjectProperty -Object $BuildProfile -Name 'wsl2Distros'
    }
    $wslDistros = @(ConvertTo-UIStringArray -Value $wslSource | ForEach-Object { ConvertTo-UILoadoutLabel -Value $_ })

    $layers = [System.Collections.Generic.List[string]]::new()
    foreach ($layer in @(ConvertTo-UIStringArray -Value (Get-UIObjectProperty -Object $desktop -Name 'layers'))) {
        if ($layer -ne 'standard') { $layers.Add((ConvertTo-UILoadoutLabel -Value $layer)) | Out-Null }
    }
    if ($modules) {
        $shell = Get-UIObjectProperty -Object $modules -Name 'shell'
        if ($shell) {
            if ([bool](Get-UIObjectProperty -Object $shell -Name 'yasb' -Fallback $false)) { $layers.Add('YASB') | Out-Null }
            if ([bool](Get-UIObjectProperty -Object $shell -Name 'komorebi' -Fallback $false)) { $layers.Add('Komorebi') | Out-Null }
            if ([bool](Get-UIObjectProperty -Object $shell -Name 'whkd' -Fallback $false)) { $layers.Add('whkd') | Out-Null }
        }
        $windhawk = Get-UIObjectProperty -Object $modules -Name 'windhawk'
        if ($windhawk -and [bool](Get-UIObjectProperty -Object $windhawk -Name 'enabled' -Fallback $false)) {
            $layers.Add('Windhawk') | Out-Null
        }
    }
    $desktopLayers = @($layers | Select-Object -Unique)
    if ($desktopLayers.Count -eq 0) { $desktopLayers = @('Standard Windows') }

    return [pscustomobject]@{
        Profile = $profileName
        Editors = $editors
        WslDistros = $wslDistros
        DesktopLayers = $desktopLayers
    }
}

$agentProfile = Read-UIJson -Path $profilePath
if (-not $agentProfile) {
    $agentProfile = [pscustomobject]@{
        profile = 'Developer'
        editors = @()
        modules = [pscustomobject]@{
            packageManagers = [pscustomobject]@{ enabled = $true }
            wsl             = [pscustomobject]@{ enabled = $false }
            shell           = [pscustomobject]@{ yasb = $false; komorebi = $false }
            windhawk        = [pscustomobject]@{ enabled = $false }
            flowEverything  = [pscustomobject]@{ enabled = $false }
        }
    }
}
$loadout = Get-UILoadoutSummary -BuildProfile $agentProfile

# ── Build step definitions from profile ──────────────────────────────────────
# Each entry: @{ Label; StateKey; Enabled; IsEditorGroup }
$stepDefs = [System.Collections.Generic.List[hashtable]]::new()

function Add-StepDef {
    param([string]$Label, [string]$StateKey, [bool]$Enabled)
    $stepDefs.Add(@{ Label = $Label; StateKey = $StateKey; Enabled = $Enabled })
}

function Test-UIAgentModuleEnabled {
    param(
        [object]$BuildProfile,
        [string]$Name
    )
    $modules = Get-UIObjectProperty -Object $BuildProfile -Name 'modules'
    if (-not $modules) { return $false }
    $cfg = Get-UIObjectProperty -Object $modules -Name $Name
    if (-not $cfg) { return $false }
    $enabled = Get-UIObjectProperty -Object $cfg -Name 'enabled'
    if ($null -ne $enabled) { return [bool]$enabled }
    foreach ($p in $cfg.PSObject.Properties) {
        if ($p.Value -is [bool] -and $p.Value) { return $true }
    }
    return $false
}

$hasPkg  = Test-UIAgentModuleEnabled -BuildProfile $agentProfile -Name 'packageManagers'
$hasWsl  = (Test-UIAgentModuleEnabled -BuildProfile $agentProfile -Name 'wsl') -or $loadout.WslDistros.Count -gt 0
$hasShell = @($loadout.DesktopLayers | Where-Object { $_ -ne 'Standard Windows' -and $_ -ne 'Windhawk' }).Count -gt 0
$hasWh   = (Test-UIAgentModuleEnabled -BuildProfile $agentProfile -Name 'windhawk') -or @($loadout.DesktopLayers | Where-Object { $_ -eq 'Windhawk' }).Count -gt 0
$hasFlow = Test-UIAgentModuleEnabled -BuildProfile $agentProfile -Name 'flowEverything'
$editors = @($loadout.Editors)
$hasEditors = $editors.Count -gt 0

Add-StepDef -Label 'Profile prep'      -StateKey 'module:profiles'         -Enabled $true
Add-StepDef -Label 'Package managers' -StateKey 'module:package-managers' -Enabled $hasPkg
Add-StepDef -Label 'WSL'              -StateKey 'module:wsl'              -Enabled $hasWsl
Add-StepDef -Label 'Desktop layers'   -StateKey 'module:tiling-desktop'   -Enabled $hasShell
Add-StepDef -Label 'Windhawk'         -StateKey 'module:windhawk'         -Enabled $hasWh
Add-StepDef -Label 'Flow Launcher & Everything' -StateKey 'module:flow-everything' -Enabled $hasFlow
Add-StepDef -Label 'Editors'          -StateKey 'module:editors'          -Enabled $hasEditors

# ── WPF load ──────────────────────────────────────────────────────────────────
try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Type -AssemblyName PresentationCore      -ErrorAction Stop
    Add-Type -AssemblyName WindowsBase           -ErrorAction Stop
} catch {
    Write-Warning "WPF unavailable: $_. Falling back to console agent."
    exit 2
}

# ── Status helpers ────────────────────────────────────────────────────────────
function ConvertTo-StatusDisplay {
    param([string]$Status)
    switch ($Status) {
        'pending'     { return @{ Icon = '○'; IconColor = '#6B7280'; Text = 'Waiting';      TextColor = '#8A8F98' } }
        'running'     { return @{ Icon = '▶'; IconColor = '#3B82F6'; Text = 'Running...';   TextColor = '#A9C7FF' } }
        'ok'          { return @{ Icon = '✓'; IconColor = '#62C370'; Text = 'Complete';     TextColor = '#9BE7A4' } }
        'failed'      { return @{ Icon = '✕'; IconColor = '#F87171'; Text = 'Failed';       TextColor = '#FFB4B4' } }
        'retryable'   { return @{ Icon = '↺'; IconColor = '#60A5FA'; Text = 'Retryable';    TextColor = '#B9D8FF' } }
        'skipped'     { return @{ Icon = '—'; IconColor = '#545B66'; Text = 'Skipped';      TextColor = '#777F8C' } }
        'scaffolded'  { return @{ Icon = '—'; IconColor = '#545B66'; Text = 'Skipped';      TextColor = '#777F8C' } }
        'needsReboot' { return @{ Icon = '↻'; IconColor = '#60A5FA'; Text = 'Restart next'; TextColor = '#B9D8FF' } }
        default       { return @{ Icon = '·'; IconColor = '#6B7280'; Text = $Status;        TextColor = '#8A8F98' } }
    }
}

$script:BrushConverter = [System.Windows.Media.BrushConverter]::new()
function New-Brush { param([string]$Color)
    $script:BrushConverter.ConvertFromString($Color)
}

$monoFont = [System.Windows.Media.FontFamily]::new('Cascadia Code, Consolas, Courier New')
$uiFont   = [System.Windows.Media.FontFamily]::new('Segoe UI Variable Text, Segoe UI')

# ── XAML window ───────────────────────────────────────────────────────────────
$xamlPath = Join-Path $agentRoot 'Start-WinWSFirstLogonUI.xaml'
if (-not (Test-Path -LiteralPath $xamlPath)) {
    Write-Warning "FirstLogon UI XAML missing: $xamlPath. Falling back to console agent."
    exit 2
}
[xml]$xaml = Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# ── Populate header ───────────────────────────────────────────────────────────
$profileName = [string]$loadout.Profile
$editorText = if ($loadout.Editors.Count -gt 0) { $loadout.Editors -join ', ' } else { 'None selected' }
$wslText = if ($loadout.WslDistros.Count -gt 0) { $loadout.WslDistros -join ', ' } else { 'None selected' }
$desktopText = if ($loadout.DesktopLayers.Count -gt 0) { $loadout.DesktopLayers -join ', ' } else { 'Standard Windows' }
$window.FindName('TxtHeader').Text = "Applying the selected live-user setup for $profileName."
$window.FindName('TxtLoadoutProfile').Text = $profileName
$window.FindName('TxtLoadoutEditors').Text = $editorText
$window.FindName('TxtLoadoutWsl').Text = $wslText
$window.FindName('TxtLoadoutDesktop').Text = $desktopText

# ── Dynamically build step rows ───────────────────────────────────────────────
$stepPanel = $window.FindName('StepPanel')
$script:StepControls = @{}   # key → @{ IconBlock; StatusBlock }

foreach ($def in $stepDefs) {
    $row = [System.Windows.Controls.Grid]::new()
    $row.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)

    $col0 = [System.Windows.Controls.ColumnDefinition]::new()
    $col0.Width = [System.Windows.GridLength]::new(22)
    $col1 = [System.Windows.Controls.ColumnDefinition]::new()
    $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $col2 = [System.Windows.Controls.ColumnDefinition]::new()
    $col2.Width = [System.Windows.GridLength]::new(110)
    $row.ColumnDefinitions.Add($col0)
    $row.ColumnDefinitions.Add($col1)
    $row.ColumnDefinitions.Add($col2)

    $display = if ($def.Enabled) {
        ConvertTo-StatusDisplay -Status 'pending'
    } else {
        ConvertTo-StatusDisplay -Status 'skipped'
    }

    $iconBlock = [System.Windows.Controls.TextBlock]::new()
    $iconBlock.Text = $display.Icon
    $iconBlock.FontFamily = $monoFont
    $iconBlock.FontSize = 13
    $iconBlock.Foreground = New-Brush $display.IconColor
    $iconBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.Grid]::SetColumn($iconBlock, 0)

    $nameBlock = [System.Windows.Controls.TextBlock]::new()
    $nameBlock.Text = $def.Label
    $nameBlock.FontFamily = $uiFont
    $nameBlock.FontSize = 13
    $nameBlock.Foreground = if ($def.Enabled) { New-Brush '#CCCCCC' } else { New-Brush '#555555' }
    $nameBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.Grid]::SetColumn($nameBlock, 1)

    $statusBlock = [System.Windows.Controls.TextBlock]::new()
    $statusBlock.Text = $display.Text
    $statusBlock.FontFamily = $monoFont
    $statusBlock.FontSize = 11.5
    $statusBlock.Foreground = New-Brush $display.TextColor
    $statusBlock.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $statusBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.Grid]::SetColumn($statusBlock, 2)

    $row.Children.Add($iconBlock)   | Out-Null
    $row.Children.Add($nameBlock)   | Out-Null
    $row.Children.Add($statusBlock) | Out-Null
    $stepPanel.Children.Add($row)   | Out-Null

    $script:StepControls[$def.StateKey] = @{
        Icon   = $iconBlock
        Status = $statusBlock
        Name   = $nameBlock
        Def    = $def
    }
}

# ── Apply step status from state object ──────────────────────────────────────
function Update-StepRow {
    param([string]$Key, [string]$Status)
    $controls = $script:StepControls[$Key]
    if (-not $controls) { return }
    $display = ConvertTo-StatusDisplay -Status $Status
    $controls.Icon.Text       = $display.Icon
    $controls.Icon.Foreground = New-Brush $display.IconColor
    $controls.Status.Text     = $display.Text
    $controls.Status.Foreground = New-Brush $display.TextColor
}

function Update-UIFromState {
    param([object]$State)
    if (-not $State) { return }
    if (-not $State.PSObject.Properties['steps']) { return }
    foreach ($pair in $script:StepControls.GetEnumerator()) {
        $key = $pair.Key
        $stepObj = $null
        try { $stepObj = $State.steps.PSObject.Properties[$key].Value } catch { }
        if ($stepObj -and $stepObj.PSObject.Properties['status']) {
            Update-StepRow -Key $key -Status ([string]$stepObj.status)
        }
    }
}

# ── Launch agent process ──────────────────────────────────────────────────────
$agentScript = Join-Path $agentRoot 'Start-WinWSAgent.ps1'
if (-not (Test-Path -LiteralPath $agentScript)) {
    $window.FindName('TxtStatus').Text = "Agent not found: $agentScript"
    $window.FindName('BtnClose').IsEnabled = $true
    $script:AgentExitCode = 1
    $null = $window.ShowDialog()
    exit 1
}

function Resolve-UIAgentHost {
    $pwsh7 = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if (Test-Path -LiteralPath $pwsh7) { return $pwsh7 }
    $sysnative = Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $sysnative) { return $sysnative }
    return Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
}

$exe = Resolve-UIAgentHost
$agentArgs = [System.Collections.Generic.List[string]]::new()
$agentArgs.AddRange([string[]]@('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$agentScript`""))
if ($Force) { $agentArgs.Add('-Force') }
$script:AgentProcess = Start-Process -FilePath $exe -ArgumentList $agentArgs.ToArray() `
    -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
if (-not $script:AgentProcess) {
    $window.FindName('TxtStatus').Text = 'Failed to start agent process.'
    $window.FindName('BtnClose').IsEnabled = $true
    $script:AgentExitCode = 1
    $null = $window.ShowDialog()
    exit 1
}

# ── DispatcherTimer: poll state.json + agent exit ─────────────────────────────
$script:LastStateRead = [datetime]::MinValue
$script:Complete = $false

$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(500)
$timer.Add_Tick({
    if ($script:Complete) { return }

    $stateObj = $null
    try {
        if (Test-Path -LiteralPath $statePath) {
            $stateObj = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    } catch { }

    if ($stateObj) {
        $window.Dispatcher.Invoke([Action]{
            Update-UIFromState -State $stateObj
        }, [System.Windows.Threading.DispatcherPriority]::Background)
    }

    if ($script:AgentProcess.HasExited) {
        $script:Complete = $true
        $timer.Stop()
        $script:AgentExitCode = [int]$script:AgentProcess.ExitCode

        $window.Dispatcher.Invoke([Action]{
            $pb = $window.FindName('FLProgressBar')
            $pb.IsIndeterminate = $false
            $pb.Value = 100
            $pb.Foreground = if ($script:AgentExitCode -eq 0) { New-Brush '#62C370' } else { New-Brush '#F87171' }

            $statusTxt = $window.FindName('TxtStatus')
            $btnClose  = $window.FindName('BtnClose')
            $btnRetry  = $window.FindName('BtnRetry')
            $btnRestart = $window.FindName('BtnRestart')

            $rebootPending = $false
            try {
                $finalState = Read-UIJson -Path $statePath
                if ($finalState -and $finalState.PSObject.Properties['run']) {
                    $runBlock = $finalState.run
                    if ($runBlock.PSObject.Properties['rebootPending']) {
                        $rebootPending = [bool]$runBlock.rebootPending
                    }
                }
                Update-UIFromState -State $finalState
            } catch { }

            if ($script:AgentExitCode -eq 0) {
                $statusTxt.Text = if ($rebootPending) {
                    'First-logon setup finished. Restart now to let Windows finish registering the selected components.'
                } else {
                    'First-logon setup finished. Your selected apps, WSL2 options, and desktop layers are ready.'
                }
                if ($rebootPending) { $btnRestart.Visibility = [System.Windows.Visibility]::Visible }
            } else {
                $statusTxt.Text = 'Some selected setup steps did not finish. Review %LOCALAPPDATA%\WinWS\Logs, then retry the failed work from here.'
                $btnRetry.Visibility = [System.Windows.Visibility]::Visible
            }
            $btnClose.IsEnabled = $true
        }, [System.Windows.Threading.DispatcherPriority]::Background)
    }
})
$timer.Start()

# ── Button handlers ───────────────────────────────────────────────────────────
$window.FindName('BtnClose').Add_Click({
    $window.Close()
})

$window.FindName('BtnRetry').Add_Click({
    $timer.Stop()
    $script:Complete = $false
    $window.FindName('BtnRetry').Visibility  = [System.Windows.Visibility]::Collapsed
    $window.FindName('BtnClose').IsEnabled   = $false
    $window.FindName('TxtStatus').Text       = ''
    $pb = $window.FindName('FLProgressBar')
    $pb.IsIndeterminate = $true
    $pb.Foreground = New-Brush '#0078D4'

    foreach ($pair in $script:StepControls.GetEnumerator()) {
        if ($pair.Value.Def.Enabled) {
            Update-StepRow -Key $pair.Key -Status 'pending'
        }
    }

    # Retry runs the agent without -Force so already-`ok` modules and tools are
    # skipped via the idempotency guard; only failed/retryable/needsReboot
    # steps are re-attempted.
    $retryArgs = [System.Collections.Generic.List[string]]::new()
    $retryArgs.AddRange([string[]]@('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$agentScript`""))
    $script:AgentProcess = Start-Process -FilePath $exe -ArgumentList $retryArgs.ToArray() `
        -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
    $timer.Start()
})

$window.FindName('BtnRestart').Add_Click({
    Start-Process -FilePath 'shutdown.exe' -ArgumentList '/r', '/t', '10', '/c', 'WinWS Setup is restarting to complete configuration.' -WindowStyle Hidden
    $window.Close()
})

# ── Drag support ─────────────────────────────────────────────────────────────
$window.Add_MouseLeftButtonDown({
    try { $window.DragMove() } catch { }
})

# ── Show (blocks until window closes) ─────────────────────────────────────────
$null = $window.ShowDialog()
exit $script:AgentExitCode
