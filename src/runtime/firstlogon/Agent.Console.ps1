#Requires -Version 7.3

function Write-AgentLog {
    param([string]$Message)
    "$(Get-Date -Format o) $Message" | Out-File (Join-Path $logDir 'WinMintAgent.log') -Append -Encoding utf8
}

function Write-AgentEvent {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Status,
        [string]$Step,
        [string]$Message,
        [hashtable]$Data = @{}
    )

    try {
        $agentEvent = [ordered]@{
            time = Get-Date -Format o
            type = $Type
        }
        if (-not [string]::IsNullOrWhiteSpace($Status)) { $agentEvent.status = $Status }
        if (-not [string]::IsNullOrWhiteSpace($Step)) { $agentEvent.step = $Step }
        if (-not [string]::IsNullOrWhiteSpace($Message)) { $agentEvent.message = $Message }
        foreach ($key in $Data.Keys) {
            if (-not $agentEvent.Contains($key)) { $agentEvent[$key] = $Data[$key] }
        }
        $json = $agentEvent | ConvertTo-Json -Depth 10 -Compress
        $json | Out-File -LiteralPath $eventLogPath -Append -Encoding utf8
        if ($EmitProgressJson) { [Console]::Out.WriteLine($json) }
    }
    catch {
        Write-AgentLog "Progress event write failed: $($_.Exception.Message)"
    }
}

function Initialize-AgentConsole {
    if (-not $InteractiveFirstLogon) { return }
    try {
        if (-not (Get-Command Write-SpectreHost -ErrorAction SilentlyContinue)) {
            $galleryCache = Join-Path $stateDir 'PSGallery'
            $null = New-Item -ItemType Directory -Path $galleryCache -Force -ErrorAction SilentlyContinue
            $manifest = @(Get-ChildItem -LiteralPath $galleryCache -Recurse -Filter 'PwshSpectreConsole.psd1' -File -ErrorAction SilentlyContinue |
                    Sort-Object FullName -Descending |
                    Select-Object -First 1)
            if (-not $manifest -and (Get-Command Save-Module -ErrorAction SilentlyContinue)) {
                $savedProgress = $ProgressPreference
                try {
                    $ProgressPreference = 'SilentlyContinue'
                    Save-Module -Name PwshSpectreConsole -Path $galleryCache -Repository PSGallery -Force -ErrorAction Stop
                }
                finally {
                    $ProgressPreference = $savedProgress
                }
                $manifest = @(Get-ChildItem -LiteralPath $galleryCache -Recurse -Filter 'PwshSpectreConsole.psd1' -File -ErrorAction SilentlyContinue |
                        Sort-Object FullName -Descending |
                        Select-Object -First 1)
            }
            if ($manifest) {
                Import-Module -Name $manifest.FullName -Force -Global -ErrorAction Stop
            }
        }
        $script:AgentConsoleReady = [bool](Get-Command Write-SpectreHost -ErrorAction SilentlyContinue)
        if ($script:AgentConsoleReady) {
            try {
                $w = [Math]::Clamp([int]$Host.UI.RawUI.WindowSize.Width, 60, 220)
                $h = [Math]::Clamp([int]$Host.UI.RawUI.WindowSize.Height, 20, 120)
                [Spectre.Console.AnsiConsole]::Console.Profile.Width = $w
                [Spectre.Console.AnsiConsole]::Console.Profile.Height = $h
            }
            catch { }
        }
    }
    catch {
        $script:AgentConsoleReady = $false
        Write-AgentLog "PwshSpectreConsole unavailable: $($_.Exception.Message)"
    }
}

function Get-AgentEscapedText {
    param([string]$Text)
    if ($script:AgentConsoleReady) { return [Spectre.Console.Markup]::Escape([string]$Text) }
    return [string]$Text
}

function Get-AgentConsoleWidth {
    try {
        return [Math]::Clamp([int]$Host.UI.RawUI.WindowSize.Width, 60, 220)
    }
    catch {
        return 80
    }
}

function Get-AgentPanelWidth {
    param(
        [int]$Preferred = 96,
        [int]$Minimum = 56
    )
    return [Math]::Min($Preferred, [Math]::Max($Minimum, (Get-AgentConsoleWidth) - 4))
}

function Write-AgentSplashTextFallback {
    return
}

function Out-AgentSpectreRenderable {
    param([Parameter(ValueFromPipeline)]$Renderable)
    process {
        if ($null -eq $Renderable) { return }
        $Renderable | Out-SpectreHost | Out-Host
    }
}

function New-AgentSpectrePanel {
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][string]$Header,
        [string]$Color = 'Grey',
        [int]$Width = 0,
        [switch]$Expand
    )

    $panelArgs = @{
        Header = $Header
        Border = 'Rounded'
        Color = $Color
    }
    if ($Expand) { $panelArgs.Expand = $true }
    if ($Width -gt 0) { $panelArgs.Width = $Width }
    return $Data | Format-SpectrePanel @panelArgs
}

function Show-AgentSplashImage {
    if (-not $InteractiveFirstLogon) { return }
    if (-not $script:AgentConsoleReady) { return }
    try {
        if ([string]::IsNullOrWhiteSpace($script:AgentConsoleSplashImagePath)) { return }
        if (-not (Test-Path -LiteralPath $script:AgentConsoleSplashImagePath -PathType Leaf)) { return }

        $renderSixel = -not [string]::IsNullOrWhiteSpace($env:WT_SESSION)
        try {
            if ([bool]$script:AgentConsoleForceSixel) {
                $renderSixel = $true
            }
        }
        catch { }

        if (-not $renderSixel) {
            Write-AgentSplashTextFallback
            return
        }
        if (-not (Get-Command Get-SpectreImage -ErrorAction SilentlyContinue)) {
            Write-AgentSplashTextFallback
            return
        }

        $maxWidth = 52
        try {
            if ([int]$script:AgentConsoleSplashMaxWidth -gt 0) {
                $maxWidth = [int]$script:AgentConsoleSplashMaxWidth
            }
        }
        catch { }
        $availableWidth = [Math]::Max(32, (Get-AgentConsoleWidth) - 4)
        $maxWidth = [Math]::Min($maxWidth, $availableWidth)
        $imageArgs = @{
            ImagePath = [string]$script:AgentConsoleSplashImagePath
            MaxWidth = $maxWidth
            Format = 'Sixel'
            Force = $true
        }
        $image = Get-SpectreImage @imageArgs
        if (Get-Command Format-SpectreAligned -ErrorAction SilentlyContinue) {
            $image | Format-SpectreAligned -HorizontalAlignment Center | Out-SpectreHost | Out-Host
        }
        else {
            $image | Out-SpectreHost | Out-Host
        }
        Write-Host ''
    }
    catch {
        Write-AgentLog "Splash image render failed: $($_.Exception.Message)"
        if ($script:AgentConsoleReady) {
            Write-AgentSplashTextFallback
        }
    }
}

function Write-AgentConsoleLine {
    param(
        [ValidateSet('Info','OK','Warn','Error','Section')][string]$Level,
        [string]$Message
    )
    if (-not $InteractiveFirstLogon) { return }
    $safe = Get-AgentEscapedText -Text $Message
    if ($script:AgentConsoleReady) {
        $prefix = switch ($Level) {
            'OK' { '[green]done[/]' }
            'Warn' { '[yellow]warn[/]' }
            'Error' { '[red]fail[/]' }
            'Section' { '[dodgerblue1]step[/]' }
            default { '[grey]run [/]' }
        }
        $null = Write-SpectreHost "$prefix  [white]$safe[/]"
        return
    }
    $color = switch ($Level) {
        'OK' { 'Green' }
        'Warn' { 'Yellow' }
        'Error' { 'Red' }
        'Section' { 'Cyan' }
        default { 'Gray' }
    }
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Show-AgentConsoleHeader {
    if (-not $InteractiveFirstLogon) { return }
    $logLabel = '%LOCALAPPDATA%\WinMint\Logs'
    try {
        if (-not [string]::IsNullOrWhiteSpace($script:AgentConsoleLogLabel)) {
            $logLabel = [string]$script:AgentConsoleLogLabel
        }
    }
    catch { }
    Show-AgentSplashImage
    if ($script:AgentConsoleReady) {
        $safeLogLabel = Get-AgentEscapedText -Text $logLabel
        $body = @(
            '[bold white]WinMint FirstLogon[/]'
            '[grey]Applying the selected first-logon preset.[/]'
            ''
            "[grey]Logs[/]  [silver]$safeLogLabel[/]"
        ) -join "`n"
        New-AgentSpectrePanel -Data $body -Header '[bold dodgerblue1]Setup[/]' -Color DodgerBlue1 -Width (Get-AgentPanelWidth -Preferred 96 -Minimum 64) |
            Out-AgentSpectreRenderable
        Write-Host ''
        return
    }
    Write-Host ''
    Write-Host 'WinMint FirstLogon' -ForegroundColor Cyan
    Write-Host "Applying the selected first-logon preset. Logs are under $logLabel." -ForegroundColor Gray
    Write-Host ''
}

function Show-AgentPlan {
    if (-not $InteractiveFirstLogon) { return }
    $shellLayers = @()
    if ($agentProfile.modules.shell.nilesoft) { $shellLayers += 'Nilesoft' }
    if ($agentProfile.modules.shell.yasb) { $shellLayers += 'YASB' }
    if ($agentProfile.modules.shell.komorebi) { $shellLayers += 'Komorebi' }
    if (Test-AgentModuleEnabled -Name 'windhawk') { $shellLayers += 'Windhawk' }
    $rows = @(
        [pscustomobject]@{ Area = 'Apps'; Selected = if (@($agentProfile.browsers).Count) { @($agentProfile.browsers) -join ', ' } else { 'None' } }
        [pscustomobject]@{ Area = 'Editors'; Selected = if (@($agentProfile.editors).Count) { @($agentProfile.editors) -join ', ' } else { 'None' } }
        [pscustomobject]@{ Area = 'WSL'; Selected = if (@($agentProfile.modules.wsl.distros).Count) { @($agentProfile.modules.wsl.distros) -join ', ' } else { 'Baseline only' } }
        [pscustomobject]@{ Area = 'Desktop'; Selected = if ($shellLayers.Count) { $shellLayers -join ', ' } else { 'Standard Windows' } }
    )
    if ($script:AgentConsoleReady) {
        $table = Format-SpectreTable -Data $rows -Property Area, Selected -Border Minimal -Color Grey -HeaderColor Grey -TextColor White
        New-AgentSpectrePanel -Data $table -Header '[bold white]Selected setup[/]' -Color Grey -Width (Get-AgentPanelWidth -Preferred 72 -Minimum 56) |
            Out-AgentSpectreRenderable
        Write-Host ''
        return
    }
    $rows | Format-Table -AutoSize
}

function Show-AgentFinalSummary {
    param([hashtable]$State)
    if (-not $InteractiveFirstLogon) { return }
    $rows = @(
        $State.steps.GetEnumerator() |
            Sort-Object Name |
            ForEach-Object {
                [pscustomobject]@{
                    Step = $_.Key
                    Status = [string]$_.Value.status
                }
            }
    )
    if ($script:AgentConsoleReady) {
        Write-SpectreHost ''
        $table = Format-SpectreTable -Data $rows -Property Step, Status -Border Minimal -Color Grey -HeaderColor Grey -TextColor White
        New-AgentSpectrePanel -Data $table -Header '[bold white]FirstLogon result[/]' -Color Grey -Width (Get-AgentPanelWidth -Preferred 68 -Minimum 56) |
            Out-AgentSpectreRenderable
        return
    }
    $rows | Format-Table -AutoSize
}

function Wait-AgentConsoleBeforeClose {
    param([bool]$Failed, [bool]$Warnings)
    if (-not $InteractiveFirstLogon) { return }
    if ($Failed) {
        Write-AgentConsoleLine -Level Error -Message "One or more selected steps failed. Review $logDir before closing this window."
        Read-Host 'Press Enter to close'
        return
    }
    if ($Warnings) {
        Write-AgentConsoleLine -Level Warn -Message "First-logon automation finished with warnings. Review $logDir for failed optional installs."
        Start-Sleep -Seconds 10
        return
    }
    Write-AgentConsoleLine -Level OK -Message 'First-logon automation finished. This window will close shortly.'
    Start-Sleep -Seconds 8
}
