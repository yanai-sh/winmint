#Requires -Version 7.3

function Limit-WinMintUiDisplayLine {
    param(
        [string]$Text,
        [int]$Max = 120
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $t = $Text.Trim()
    if ($t.Length -le $Max) { return $t }
    return $t.Substring(0, [Math]::Max(0, $Max - 1)).TrimEnd() + '…'
}

function Format-WinMintUiBuildHeadline {
    param(
        [string]$Stage,
        [string]$Level,
        [string]$Message
    )
    $rawMsg = [string]$Message
    if ($Level -eq 'Section') {
        $rawMsg = $rawMsg -replace '^Starting\s+', ''
    }
    $m = Limit-WinMintUiDisplayLine -Text $rawMsg -Max 110
    if ([string]::IsNullOrWhiteSpace($m)) { $m = 'Working…' }

    $s = [string]$Stage
    if ([string]::IsNullOrWhiteSpace($s)) {
        return $m
    }

    $label = switch -Regex ($s) {
        '^Validate' { 'Checking prerequisites' }
        '^Profile' { 'Saving profile' }
        '^Report' { 'Writing reports' }
        '^DryRun' { 'Dry run' }
        '^Start' { 'Starting' }
        '^Build$' { 'Running pipeline' }
        'Stage ISO' { 'Staging ISO contents' }
        'Service WIM' { 'Servicing Windows image' }
        'Assemble ISO' { 'Assembling output ISO' }
        '^Clean' { 'Cleaning work folders' }
        '^Extract' { 'Copying files' }
        '^Mount' { 'Mounting image' }
        '^Drivers' { 'Adding drivers' }
        '^Packages' { 'Staging packages' }
        '^Tweaks' { 'Applying tweaks' }
        '^Unattend' { 'Writing unattended setup' }
        '^Dismount' { 'Saving image' }
        '^ISO' { 'Building ISO' }
        default {
            $short = ($s -replace '^Starting\s+', '' -replace '^Completed\s+', '').Trim()
            if ($short.Length -gt 36) { $short = $short.Substring(0, 33) + '…' }
            if ([string]::IsNullOrWhiteSpace($short)) { 'Working' } else { [cultureinfo]::CurrentCulture.TextInfo.ToTitleCase($short.ToLowerInvariant()) }
        }
    }

    if ($Level -eq 'Section') {
        return "$label — $m"
    }
    return "$label · $m"
}

function Test-WinMintUiBuildLogPanelWorthy {
    param(
        [string]$Stage,
        [string]$Level
    )
    if ($Level -in @('OK', 'Warn', 'Error', 'Section')) { return $true }
    return -not [string]::IsNullOrWhiteSpace($Stage)
}

function Add-WinMintUiLogEntry {
    param(
        [Parameter(Mandatory)][object]$State,
        [string]$Level,
        [string]$Message
    )

    [void]$State.Build.LogText.AppendLine("[$Level] $Message")
}

function Stop-WinMintUiBuildPump {
    $c = Get-WinMintUiAppContextOptional
    if ($null -eq $c) { return }
    $b = $c.Build
    if ($null -ne $b.DispatcherPump) {
        try { $b.DispatcherPump.Stop() } catch {}
        $b.DispatcherPump = $null
    }
    if ($null -ne $b.Job) {
        Stop-Job -Job $b.Job -ErrorAction SilentlyContinue
        Remove-Job -Job $b.Job -Force -ErrorAction SilentlyContinue
        $b.Job = $null
    }
    $b.Messages = $null
}

function Start-WinMintUiBuild {
    param(
        [Parameter(Mandatory)][object]$State,
        [System.Windows.Window]$Window,
        [switch]$DryRun
    )

    # Reset progress bar and status text
    $bar = $Window.FindName('BuildProgress')
    if ($null -ne $bar) {
        $bar.Value = 0
        $bar.IsIndeterminate = $true
    }

    # Clear previous logs
    $panel = $Window.FindName('LogPanel')
    if ($null -ne $panel) {
        $panel.Children.Clear()
    }
    [void]$State.Build.LogText.Clear()

    Stop-WinMintUiBuildPump

    # Generate profile contract using ProfileAdapter service
    $buildProfile = New-WinMintUiBuildProfile -State $State -IncludeSecrets

    $bd = (Get-WinMintUiAppContext).Build
    $bd.Messages = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()

    $capturedProfile = $buildProfile
    $capturedScriptDir = $State.RepositoryRoot
    $capturedEnginePath = Get-WinMintPath -Name EngineEntry
    $capturedDryRun = [bool]$DryRun
    $capturedBuildMessages = $bd.Messages

    # Launch build pipeline in the background using ThreadJob
    $bd.Job = Start-ThreadJob -ScriptBlock {
        $buildProfile = $using:capturedProfile
        $outDir       = $using:capturedScriptDir
        $enginePath   = $using:capturedEnginePath
        $msgs         = $using:capturedBuildMessages

        $log = {
            param($l, $t)
            $msgs.Enqueue(@{Kind='Log'; Level=$l; Text=$t})
        }.GetNewClosure()

        $status = {
            param($t)
            $msgs.Enqueue(@{Kind='Status'; Text=$t})
        }.GetNewClosure()

        try {
            $isoName = [System.IO.Path]::GetFileName([string]$buildProfile.source.isoPath)
            if ([string]::IsNullOrWhiteSpace($isoName)) { $isoName = 'source ISO' }

            $editionLog = ($buildProfile.target.editionMode -eq 'Fixed' -and $buildProfile.target.edition) ?
                [string]$buildProfile.target.edition :
                'Target license (Windows picks edition on the device)'

            $driverBits = switch ([string]$buildProfile.drivers.source) {
                'None' { 'No extra driver pack' }
                'Host' { 'Driver pack from this PC' }
                'Custom' {
                    $p = [string]$buildProfile.drivers.path
                    if ([string]::IsNullOrWhiteSpace($p)) { 'Custom drivers (path not set)' }
                    else {
                        $leaf = Split-Path -LiteralPath $p.TrimEnd('\') -Leaf
                        if ([string]::IsNullOrWhiteSpace($leaf)) { 'Custom driver folder' }
                        else { "Custom drivers: $leaf" }
                    }
                }
                default { 'Drivers: ' + [string]$buildProfile.drivers.source }
            }

            & $status "Preparing build — $isoName ($($buildProfile.source.architecture)) for $($buildProfile.target.device)."
            & $log 'Section' 'Build summary'
            & $log 'Info' "Edition: $editionLog"
            & $log 'Info' "PC name $($buildProfile.identity.computerName) · account $($buildProfile.identity.accountName)"
            & $log 'Info' $driverBits

            # Load the main engine
            & $status 'Loading WinMint engine (this can take a few seconds)…'
            . $enginePath
            Initialize-WinMintEngine -RepositoryRoot $outDir -DryRun:$using:capturedDryRun

            $progressHandler = {
                param($progressEvent)
                $msgs.Enqueue(@{Kind='Progress'; Level=$progressEvent.Level; Stage=$progressEvent.Stage; Message=$progressEvent.Message})
            }.GetNewClosure()

            & $status 'Clearing leftover disk-image mounts from earlier runs…'
            try {
                Invoke-Win11IsoStartupCleanup
                & $log 'OK' 'Stale mounts cleared.'
            } catch {
                & $log 'Warn' "Mount cleanup skipped ($($_.Exception.Message))"
            }

            # Invoke build execution
            & $status 'Running build — you will see phases below; long DISM steps can take several minutes.'
            $result = Start-WinMintBuild -BuildProfile $buildProfile -DryRun:$using:capturedDryRun -ProgressHandler $progressHandler
            & $log 'OK' "Build report: $([System.IO.Path]::GetFileName([string]$result.Paths.Json))"
            $msgs.Enqueue(@{Kind='Complete'; Success=$true; Output=$result.OutputPath})
        } catch {
            $plain = if ($_.Exception.Message) { [string]$_.Exception.Message } else { "$_" }
            $msgs.Enqueue(@{Kind='Log'; Level='Error'; Text = "Build stopped: $plain" })
            $msgs.Enqueue(@{Kind='Complete'; Success=$false; Output=''})
        }
    }

    # DispatcherTimer progress pump - drains queue messages on the UI thread every 40 ms
    $bd.DispatcherPump = [System.Windows.Threading.DispatcherTimer]::new()
    $bd.DispatcherPump.Interval = [TimeSpan]::FromMilliseconds(40)
    $bd.DispatcherPump.Add_Tick({
        # Do not close over $bd — dispatcher ticks under StrictMode won't see Start-WinMintUiBuild locals.
        $slotPump = Get-WinMintUiBuildSlot
        $pump = if ($null -ne $slotPump) { $slotPump.DispatcherPump } else { $null }
        $ok = Invoke-WinMintUiRoutedAction -Source 'Build.Pump' -Action {
            $app = Get-WinMintUiAppContext
            $win = $app.Window
            $uiState = $app.State
            $slot = $app.Build
            $msg = $null
            $done = $false
            while (-not $done -and $slot.Messages.TryDequeue([ref]$msg)) {
                switch ($msg.Kind) {
                    'Log' {
                        Add-WinMintUiBuildLogEntry -State $uiState -Window $win -Level $msg.Level -Text $msg.Text
                    }
                    'Status' {
                        Set-WinMintUiLaunchStatus -Message $msg.Text
                    }
                    'Progress' {
                        $lvl = [string]$msg.Level
                        $stg = [string]$msg.Stage
                        $txt = [string]$msg.Message
                        if (Test-WinMintUiBuildLogPanelWorthy -Stage $stg -Level $lvl) {
                            Add-WinMintUiBuildLogEntry -State $uiState -Window $win -Level $lvl -Text $txt
                        }
                        Set-WinMintUiLaunchStatus -Message (Format-WinMintUiBuildHeadline -Stage $stg -Level $lvl -Message $txt)
                        if (-not [string]::IsNullOrWhiteSpace($stg)) {
                            Update-WinMintUiBuildProgressBar -Window $win -Stage $stg
                        }
                    }
                    'Complete' {
                        $uiState.Build.IsRunning = $false
                        $slot.DispatcherPump.Stop()
                        $slot.DispatcherPump = $null

                        if ($null -ne $slot.Job) {
                            $slot.Job | Remove-Job -Force -ErrorAction SilentlyContinue
                            $slot.Job = $null
                        }

                        $resultBrush = $msg.Success ? $win.Resources['SuccessBrush'] : $win.Resources['DangerBrush']
                        $progressBar = $win.FindName('BuildProgress')
                        if ($null -ne $progressBar) {
                            $progressBar.IsIndeterminate = $false
                            $progressBar.Value = 100
                            $progressBar.Foreground = $resultBrush
                        }

                        $completedStatus = $msg.Success ? 'Build finished successfully.' : 'Build did not finish — see the last lines above.'
                        Set-WinMintUiLaunchStatus -Message $completedStatus

                        if ($msg.Success -and $msg.Output) {
                            $uiState.Build.OutputPath = $msg.Output
                            $out = [string]$msg.Output
                            $leaf = [System.IO.Path]::GetFileName($out)
                            $dir = [System.IO.Path]::GetDirectoryName($out)
                            Add-WinMintUiBuildLogEntry -State $uiState -Window $win -Level 'OK' -Text "Output ISO: $leaf  ($dir)"
                        } else {
                            Add-WinMintUiBuildLogEntry -State $uiState -Window $win -Level 'Error' -Text 'Build ended with errors.'
                        }

                        $done = $true
                    }
                }
            }
        }
        if (-not $ok) {
            try { $pump.Stop() } catch {}
        }
    })
    $bd.DispatcherPump.Start()
}

function Add-WinMintUiBuildLogEntry {
    param(
        [object]$State,
        [System.Windows.Window]$Window,
        [string]$Level,
        [string]$Text
    )

    Add-WinMintUiLogEntry -State $State -Level $Level -Message $Text

    $panel = $Window.FindName('LogPanel')
    if ($null -eq $panel) { return }

    $textBlock = [System.Windows.Controls.TextBlock]::new()
    $display = Limit-WinMintUiDisplayLine -Text $Text -Max 200
    $textBlock.Text = if ($Level -eq 'Section') { $display } else { "· $display" }
    $textBlock.FontSize = 12
    $textBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $textBlock.Margin = [System.Windows.Thickness]::new(0, 2, 0, 2)

    # Style lines based on level
    $brush = switch ($Level) {
        'OK'      { $Window.Resources['SuccessBrush'] }
        'Warn'    { $Window.Resources['SystemAccentColorSecondaryBrush'] ?? $Window.Resources['AccentBrush'] }
        'Error'   { $Window.Resources['DangerBrush'] }
        'Section' { $Window.Resources['AccentBrush'] }
        default   { $Window.Resources['TextSecondaryBrush'] }
    }
    if ($brush) { $textBlock.Foreground = $brush }
    if ($Level -eq 'Section') { $textBlock.FontWeight = [System.Windows.FontWeights]::SemiBold }

    $panel.Children.Add($textBlock) | Out-Null

    # Scroll the log panel container to bottom
    $scroll = $Window.FindName('LogScrollViewer')
    if ($null -ne $scroll) {
        $scroll.ScrollToEnd()
    }
}

function Update-WinMintUiBuildProgressBar {
    param(
        [System.Windows.Window]$Window,
        [string]$Stage
    )

    $bar = $Window.FindName('BuildProgress')
    if ($null -eq $bar) { return }

    $bar.IsIndeterminate = $false

    $percent = switch -Regex ($Stage) {
        'Validate'     { 5 }
        'Profile'      { 10 }
        'Report'       { 15 }
        'DryRun'       { 18 }
        'Clean'        { 20 }
        'Extract'      { 35 }
        'Mount'        { 50 }
        'Drivers'      { 65 }
        'Packages'     { 75 }
        'Tweaks'       { 85 }
        'Unattend'     { 90 }
        'Dismount'     { 95 }
        'Stage ISO'    { 28 }
        'Service WIM'  { 62 }
        'Assemble ISO' { 88 }
        'ISO'          { 98 }
        '^Build$'      { 22 }
        default {
            $current = $bar.Value
            [Math]::Min(97, $current + 0.4)
        }
    }

    $bar.Value = $percent
}
