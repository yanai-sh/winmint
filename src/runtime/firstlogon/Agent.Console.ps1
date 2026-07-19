#Requires -Version 7.6

$script:AgentStepPlanTotal = 0
$script:AgentStepCompleted = 0

# Shared One Half Dark theme (same file as engine Logging).
$script:WinMintConsoleThemePath = Join-Path $PSScriptRoot '..\WinMint.ConsoleTheme.ps1'
if ((Test-Path -LiteralPath $script:WinMintConsoleThemePath) -and
    -not (Get-Command Get-WinMintConsoleTheme -ErrorAction SilentlyContinue)) {
    . $script:WinMintConsoleThemePath
}

function Get-AgentConsoleStepLabel {
    param([Parameter(Mandatory)][string]$StepKey)

    if ($StepKey -match '^module:(.+)$') {
        $stepName = $Matches[1]
        try {
            $module = @(
                Get-WinMintAgentModuleCatalog |
                    Where-Object { [string]$_.RuntimeStepName -eq $stepName } |
                    Select-Object -First 1
            )
            if ($module) { return [string]$module.Title }
        }
        catch { }
        return $stepName
    }
    if ($StepKey -match '^tool:(.+)$') {
        $toolId = $Matches[1]
        try {
            $tool = Get-AgentManifestTool -Id $toolId
            if ($tool -and $tool.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$tool.name)) {
                return [string]$tool.name
            }
        }
        catch { }
        return $toolId
    }
    return $StepKey
}

function Initialize-AgentConsoleProgress {
    if (-not (Get-WinMintAgentContext).Interactive) { return }
    try {
        $plan = @(New-WinMintAgentRuntimeStepPlan)
        $script:AgentStepPlanTotal = @($plan | Where-Object { $_.Enabled }).Count
        $script:AgentStepCompleted = 0
    }
    catch {
        $script:AgentStepPlanTotal = 0
        $script:AgentStepCompleted = 0
    }
}

function Write-AgentLog {
    param([string]$Message)
    $logDir = $null
    try { $logDir = (Get-WinMintAgentContext).LogDir } catch { }
    if ([string]::IsNullOrWhiteSpace($logDir)) { return }
    "$(Get-Date -Format o) $Message" | Out-File (Join-Path $logDir 'WinMintAgent.log') -Append -Encoding utf8
}

function Show-AgentEventInConsole {
    param(
        [Parameter(Mandatory)][string]$Type,
        [string]$Status,
        [string]$Step,
        [string]$Message,
        [hashtable]$Data = @{}
    )

    if (-not (Get-WinMintAgentContext).Interactive) { return }

    switch ($Type) {
        'command' {
            if ($Status -eq 'running') {
                $filePath = if ($Data.ContainsKey('filePath')) { [string]$Data.filePath } else { '' }
                $displayArgs = if ($Data.ContainsKey('displayArgs')) { [string]$Data.displayArgs } else { '' }
                $name = if ($filePath) { [IO.Path]::GetFileName($filePath) } else { 'command' }
                Write-AgentConsoleLine -Level Info -Message "Running $name $displayArgs".TrimEnd()
            }
            elseif ($Status -eq 'failed') {
                $exitCode = if ($Data.ContainsKey('exitCode')) { [string]$Data.exitCode } else { '?' }
                Write-AgentConsoleLine -Level Error -Message "$Message (exit $exitCode)"
                $stderr = if ($Data.ContainsKey('stderr')) { [string]$Data.stderr } else { '' }
                if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                    Write-AgentConsoleLine -Level Info -Message "stderr log: $stderr"
                }
            }
            return
        }
        'step' {
            $stepLabel = Get-AgentConsoleStepLabel -StepKey $(if ($Step) { $Step } else { '' })
            if ([string]::IsNullOrWhiteSpace($stepLabel) -and $Step) {
                $stepLabel = if ($Step -match '^module:(.+)$') { $Matches[1] } elseif ($Step -match '^tool:(.+)$') { $Matches[1] } else { $Step }
            }
            switch ($Status) {
                'running' {
                    if ($script:AgentStepPlanTotal -gt 0) {
                        $current = [Math]::Min($script:AgentStepCompleted + 1, $script:AgentStepPlanTotal)
                        Write-AgentConsoleLine -Level Info -Message "Step $current of $($script:AgentStepPlanTotal): $stepLabel"
                    }
                    else {
                        Write-AgentConsoleLine -Level Section -Message "Starting $stepLabel."
                    }
                }
                'ok' {
                    if ($Message -match 'already completed') {
                        Write-AgentConsoleLine -Level OK -Message "$stepLabel already completed."
                    }
                    elseif ($Message -match 'installed|completed') {
                        Write-AgentConsoleLine -Level OK -Message $Message
                    }
                    else {
                        Write-AgentConsoleLine -Level OK -Message "$stepLabel finished: ok."
                    }
                }
                'skipped' {
                    if ($Message -match 'is not selected') {
                        Write-AgentConsoleLine -Level Info -Message "$stepLabel not selected."
                    }
                    elseif ($Data.ContainsKey('error') -or $Message -match 'not available') {
                        Write-AgentConsoleLine -Level Warn -Message $Message
                    }
                }
                'failed' {
                    $errorText = if ($Data.ContainsKey('error')) { [string]$Data.error } else { $Message }
                    if ($Message -match 'could not start') {
                        Write-AgentConsoleLine -Level Error -Message "$stepLabel could not start."
                    }
                    else {
                        Write-AgentConsoleLine -Level Error -Message "$stepLabel failed: $errorText"
                    }
                }
                'needsReboot' {
                    Write-AgentConsoleLine -Level Warn -Message "$stepLabel finished; reboot may be required before everything is available."
                }
                'retryable' {
                    Write-AgentConsoleLine -Level Warn -Message "$stepLabel finished with retryable failures; see logs for details."
                }
                default {
                    if ($Message -match 'finished:') {
                        $level = if ($Status -eq 'ok') { 'OK' } else { 'Warn' }
                        Write-AgentConsoleLine -Level $level -Message $Message
                    }
                }
            }
            if ($Status -in @('ok', 'failed', 'skipped', 'needsReboot', 'retryable')) {
                $script:AgentStepCompleted++
            }
            return
        }
        'install' {
            if ($Status -eq 'running') {
                Write-AgentConsoleLine -Level Section -Message $Message
            }
            elseif ($Status -eq 'failed') {
                $errorText = if ($Data.ContainsKey('error')) { [string]$Data.error } else { $Message }
                Write-AgentConsoleLine -Level Error -Message $errorText
            }
            return
        }
        'download' {
            if ($Status -eq 'running') {
                Write-AgentConsoleLine -Level Info -Message $Message
            }
            elseif ($Status -eq 'ok') {
                Write-AgentConsoleLine -Level OK -Message $Message
            }
            elseif ($Status -eq 'failed') {
                Write-AgentConsoleLine -Level Error -Message $Message
            }
            return
        }
        'notice' {
            Write-AgentConsoleLine -Level OK -Message $Message
            return
        }
        'hook' {
            Write-AgentConsoleLine -Level Warn -Message $Message
            return
        }
        'user' {
            $level = switch ($Status) {
                'ok' { 'OK' }
                'warn' { 'Warn' }
                'error' { 'Error' }
                'section' { 'Section' }
                default { 'Info' }
            }
            Write-AgentConsoleLine -Level $level -Message $Message
            return
        }
        'run' {
            switch ($Status) {
                'failed' {
                    Write-AgentConsoleLine -Level Error -Message $Message
                    if ($Data.ContainsKey('failedSteps') -and @($Data.failedSteps).Count -gt 0) {
                        $labels = @($Data.failedSteps | ForEach-Object { Get-AgentConsoleStepLabel -StepKey ([string]$_) })
                        Write-AgentConsoleLine -Level Error -Message "Failed steps: $($labels -join ', ')"
                    }
                    if ($Data.ContainsKey('rebootPending') -and [bool]$Data.rebootPending) {
                        Write-AgentConsoleLine -Level Warn -Message 'A reboot may be required before retrying.'
                    }
                }
                'ok' {
                    $level = if ($Data.ContainsKey('warningSteps') -and @($Data.warningSteps).Count -gt 0) { 'Warn' } else { 'OK' }
                    Write-AgentConsoleLine -Level $level -Message $Message
                    if ($Data.ContainsKey('warningSteps') -and @($Data.warningSteps).Count -gt 0) {
                        $labels = @($Data.warningSteps | ForEach-Object { Get-AgentConsoleStepLabel -StepKey ([string]$_) })
                        Write-AgentConsoleLine -Level Warn -Message "Warnings: $($labels -join ', ')"
                    }
                    if ($Data.ContainsKey('rebootPending') -and [bool]$Data.rebootPending) {
                        Write-AgentConsoleLine -Level Warn -Message 'Windows reports a pending reboot.'
                    }
                }
                default {
                    if ($Message -match 'Package manifest missing') {
                        Write-AgentConsoleLine -Level Error -Message $Message
                    }
                }
            }
            return
        }
        'cleanup' {
            if ($Status -eq 'ok') {
                Write-AgentConsoleLine -Level OK -Message $Message
            }
            return
        }
        default {
            if ($Type -eq 'info') {
                Write-AgentConsoleLine -Level Info -Message $Message
            }
        }
    }
}

function Write-AgentUserNotice {
    param(
        [ValidateSet('Info','OK','Warn','Error','Section')][string]$Level = 'Info',
        [Parameter(Mandatory)][string]$Message
    )
    Write-AgentEvent -Type 'user' -Status $Level.ToLowerInvariant() -Message $Message
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
        $ctx = Get-WinMintAgentContext
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
        $json | Out-File -LiteralPath $ctx.EventLogPath -Append -Encoding utf8
        if ($ctx.EmitProgressJson) { [Console]::Out.WriteLine($json) }
        Show-AgentEventInConsole -Type $Type -Status $Status -Step $Step -Message $Message -Data $Data
    }
    catch {
        Write-AgentLog "Progress event write failed: $($_.Exception.Message)"
    }
}

function Initialize-AgentConsole {
    if (-not (Get-WinMintAgentContext).Interactive) { return }
    try {
        if (-not (Get-Command Write-SpectreHost -ErrorAction SilentlyContinue)) {
            $galleryCache = Join-Path (Get-WinMintAgentContext).StateDir 'PSGallery'
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
    if (-not (Get-WinMintAgentContext).Interactive) { return }
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
    if (-not (Get-WinMintAgentContext).Interactive) { return }
    $safe = Get-AgentEscapedText -Text $Message
    if ($script:AgentConsoleReady) {
        $logLevel = switch ($Level) {
            'OK' { 'OK' }
            'Warn' { 'WARN' }
            'Error' { 'ERROR' }
            'Section' { 'SECTION' }
            default { 'INFO' }
        }
        if (Get-Command Format-WinMintConsoleLineMarkup -ErrorAction SilentlyContinue) {
            $null = Write-SpectreHost (Format-WinMintConsoleLineMarkup -Level $logLevel -Message $Message -SafeMessage $safe)
            return
        }
        $null = Write-SpectreHost "[#61afef]│[/] [#5c6370]$((Get-Date).ToString('HH:mm:ss'))[/]  [bold #282c34 on #61afef] RUN [/]  [#dcdfe4]$safe[/]"
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
    if (-not (Get-WinMintAgentContext).Interactive) { return }
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
        $setupAccent = if (Get-Command Get-WinMintConsoleAccentColor -ErrorAction SilentlyContinue) {
            Get-WinMintConsoleAccentColor
        } else { '#61afef' }
        New-AgentSpectrePanel -Data $body -Header "[bold $setupAccent]Setup[/]" -Color $setupAccent -Width (Get-AgentPanelWidth -Preferred 96 -Minimum 64) |
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
    if (-not (Get-WinMintAgentContext).Interactive) { return }
    Initialize-AgentConsoleProgress
    $agentProfile = (Get-WinMintAgentContext).AgentProfile
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
    if (-not (Get-WinMintAgentContext).Interactive) { return }
    $rows = @(
        $State.steps.GetEnumerator() |
            Sort-Object Name |
            ForEach-Object {
                $stepValue = $_.Value
                $notes = ''
                if ($stepValue -and $stepValue.PSObject.Properties['error'] -and -not [string]::IsNullOrWhiteSpace([string]$stepValue.error)) {
                    $notes = [string]$stepValue.error
                }
                elseif ([string]$stepValue.status -eq 'needsReboot') {
                    $notes = 'Reboot may be required'
                }
                [pscustomobject]@{
                    Step = Get-AgentConsoleStepLabel -StepKey ([string]$_.Key)
                    Status = [string]$stepValue.status
                    Notes = $notes
                }
            }
    )
    if ($script:AgentConsoleReady) {
        Write-SpectreHost ''
        $table = Format-SpectreTable -Data $rows -Property Step, Status, Notes -Border Minimal -Color Grey -HeaderColor Grey -TextColor White
        New-AgentSpectrePanel -Data $table -Header '[bold white]FirstLogon result[/]' -Color Grey -Width (Get-AgentPanelWidth -Preferred 68 -Minimum 56) |
            Out-AgentSpectreRenderable
        return
    }
    $rows | Format-Table -AutoSize
}

function Wait-AgentConsoleBeforeClose {
    param([bool]$Failed, [bool]$Warnings)
    if (-not (Get-WinMintAgentContext).Interactive) { return }
    if ((Get-Command Test-AgentRebootPending -ErrorAction SilentlyContinue) -and (Test-AgentRebootPending)) {
        Write-AgentConsoleLine -Level Warn -Message 'Windows reports a pending reboot. Restart when convenient; sign in again if setup did not finish.'
    }
    if ($Failed) {
        Write-AgentConsoleLine -Level Error -Message "One or more selected steps failed. Review $((Get-WinMintAgentContext).LogDir) before closing this window."
        Read-Host 'Press Enter to close'
        return
    }
    if ($Warnings) {
        Write-AgentConsoleLine -Level Warn -Message "First-logon automation finished with warnings. Review $((Get-WinMintAgentContext).LogDir) for failed optional installs."
        Start-Sleep -Seconds 10
        return
    }
    Write-AgentConsoleLine -Level OK -Message 'First-logon automation finished. This window will close shortly.'
    Start-Sleep -Seconds 8
}

