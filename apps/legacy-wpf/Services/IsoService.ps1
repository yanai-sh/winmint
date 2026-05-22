#Requires -Version 7.3

function Set-WinMintUiIsoPath {
    param(
        [Parameter(Mandatory)][object]$State,
        [string]$Path
    )

    $State.Iso.Path = $Path
    $State.Iso.State = [WinMintIsoState]::Idle
    $State.Iso.Error = ''
    $State.Iso.Architecture = ''
    $State.Iso.Editions = @()
}

function Stop-WinMintUiIsoVerification {
    $iv = Get-WinMintUiIsoVerificationSlot
    if ($null -ne $iv -and $null -ne $iv.DispatcherPoll) {
        try { $iv.DispatcherPoll.Stop() } catch {}
        $iv.DispatcherPoll = $null
    }

    $journalPaths = @()
    if (Get-Command Get-WinMintUiIsoMountJournalFile -ErrorAction SilentlyContinue) {
        $jf = Get-WinMintUiIsoMountJournalFile
        if (Test-Path -LiteralPath $jf) {
            try {
                $journalPaths = @(Get-Content -LiteralPath $jf -ErrorAction Stop | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }
            catch {}
        }
    }

    $stateIso = ''
    $ctx = Get-WinMintUiAppContextOptional
    if ($null -ne $ctx) {
        $stateIso = [string]$ctx.State.Iso.Path
    }

    if ($null -ne $iv -and $null -ne $iv.Job) {
        Stop-Job -Job $iv.Job -ErrorAction SilentlyContinue
        Remove-Job -Job $iv.Job -Force -ErrorAction SilentlyContinue
        $iv.Job = $null
    }

    try { Import-Module Storage -ErrorAction SilentlyContinue | Out-Null } catch {}
    $pathsToDismount = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in @($stateIso) + @($journalPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($p)) { [void]$pathsToDismount.Add($p.Trim()) }
    }
    foreach ($p in $pathsToDismount) {
        try { $null = Dismount-DiskImage -ImagePath $p -ErrorAction SilentlyContinue } catch {}
    }
    if (Get-Command Clear-WinMintUiIsoMountJournal -ErrorAction SilentlyContinue) {
        Clear-WinMintUiIsoMountJournal
    }
}

function Sync-WinMintUiIsoControls {
    param([Parameter(Mandatory)][object]$State)

    if (Get-Command Sync-WinMintUiStartControlsFromState -ErrorAction SilentlyContinue) {
        Sync-WinMintUiStartControlsFromState -State $State
    }
    if (Get-Command Update-WinMintUiStateProbe -ErrorAction SilentlyContinue) {
        Update-WinMintUiStateProbe
    }
}

function Start-WinMintUiIsoVerification {
    param(
        [Parameter(Mandatory)][object]$State,
        [System.Windows.Window]$Window
    )

    Stop-WinMintUiIsoVerification

    $isoPath = [string]$State.Iso.Path
    if ([string]::IsNullOrWhiteSpace($isoPath) -or -not (Test-Path -LiteralPath $isoPath)) {
        $State.Iso.State = [WinMintIsoState]::Error
        $State.Iso.Error = 'Select a readable Windows ISO.'
        Sync-WinMintUiIsoControls -State $State
        return
    }

    $State.Iso.State = [WinMintIsoState]::Verifying
    $State.Iso.Error = ''
    $State.Iso.Architecture = ''
    $State.Iso.Editions = @()
    Sync-WinMintUiIsoControls -State $State

    if (Get-Command Set-WinMintUiIsoMountJournalPath -ErrorAction SilentlyContinue) {
        Set-WinMintUiIsoMountJournalPath -Path $isoPath
    }

    $iv = Get-WinMintUiIsoVerificationSlot
    if ($null -eq $iv) { return }

    $iv.Job = Start-ThreadJob -ScriptBlock {
        param([string]$Path)

        $result = [ordered]@{
            Ok           = $false
            Error        = ''
            Architecture = ''
            Editions     = @()
            FileName     = [System.IO.Path]::GetFileName($Path)
        }

        try {
            Import-Module Dism -ErrorAction Stop
            Import-Module Storage -ErrorAction Stop

            # NoDriveLetter avoids a new drive letter (stops Explorer auto-opening the mount).
            $mounted = Mount-DiskImage -ImagePath $Path -Access ReadOnly -NoDriveLetter -PassThru -ErrorAction Stop
            try {
                $volume = @($mounted | Get-Volume -ErrorAction Stop)[0]
                $root = if ($volume.DriveLetter) {
                    "$($volume.DriveLetter):\"
                } elseif ($volume.Path) {
                    [string]$volume.Path
                } else {
                    throw 'ISO mounted, but Windows did not expose a readable volume.'
                }

                $wim = Join-Path $root 'sources\install.wim'
                $esd = Join-Path $root 'sources\install.esd'
                $imagePath = if (Test-Path -LiteralPath $wim) {
                    $wim
                } elseif (Test-Path -LiteralPath $esd) {
                    $esd
                } else {
                    throw 'This ISO is missing sources\install.wim or sources\install.esd.'
                }

                $images = @(Get-WindowsImage -ImagePath $imagePath -ErrorAction Stop | Sort-Object ImageIndex)
                if ($images.Count -lt 1) { throw 'No install images found in the source ISO.' }

                $firstIndex = [int]$images[0].ImageIndex
                $info = Get-WindowsImage -ImagePath $imagePath -Index $firstIndex -ErrorAction Stop
                $result.Architecture = switch ([int]$info.Architecture) {
                    9 { 'amd64' }
                    12 { 'arm64' }
                    0 { 'x86' }
                    default { "arch$([int]$info.Architecture)" }
                }
                $result.Editions = @($images | ForEach-Object { [string]$_.ImageName })
                $result.Ok = $true
            } finally {
                Dismount-DiskImage -ImagePath $Path -ErrorAction SilentlyContinue | Out-Null
            }
        } catch {
            try { Dismount-DiskImage -ImagePath $Path -ErrorAction SilentlyContinue | Out-Null } catch {}
            $result.Error = $_.Exception.Message
        }

        [pscustomobject]$result
    } -ArgumentList $isoPath

    $iv.StartedAt = Get-Date
    $iv.DispatcherPoll = [System.Windows.Threading.DispatcherTimer]::new()
    $iv.DispatcherPoll.Interval = [System.TimeSpan]::FromMilliseconds(250)
    $iv.DispatcherPoll.Add_Tick({
        # Do not close over $iv — WPF timer ticks under StrictMode won't see Start-WinMintUiIsoVerification locals.
        $slotOuter = Get-WinMintUiIsoVerificationSlot
        $poll = if ($null -ne $slotOuter) { $slotOuter.DispatcherPoll } else { $null }
        $ok = Invoke-WinMintUiRoutedAction -Source 'IsoVerify.Poll' -Action {
            $ctxInner = Get-WinMintUiAppContextOptional
            $uiState = if ($null -ne $ctxInner) { $ctxInner.State } else { $null }
            $slot = Get-WinMintUiIsoVerificationSlot
            if ($null -eq $slot -or $null -eq $uiState) {
                if ($null -ne $poll) { $poll.Stop() }
                return
            }

            if ($null -eq $slot.Job) {
                if ($null -ne $slot.DispatcherPoll) { $slot.DispatcherPoll.Stop() }
                return
            }

            if ($slot.Job.State -eq 'Running') {
                if (((Get-Date) - $slot.StartedAt).TotalSeconds -lt 60) { return }

                $path = [string]$uiState.Iso.Path
                Stop-WinMintUiIsoVerification
                try { Dismount-DiskImage -ImagePath $path -ErrorAction SilentlyContinue | Out-Null } catch {}
                $uiState.Iso.State = [WinMintIsoState]::Error
                $uiState.Iso.Error = "Couldn't read the ISO within 60 seconds. Try selecting it again, or open it in Explorer first to confirm Windows can read it."
                $uiState.Iso.Architecture = ''
                $uiState.Iso.Editions = @()
                Sync-WinMintUiIsoControls -State $uiState
                return
            }

            $slot.DispatcherPoll.Stop()
            $verification = $null
            try {
                $verification = Receive-Job -Job $slot.Job -ErrorAction SilentlyContinue
            } catch {
                $verification = $null
            }
            if ($null -eq $verification) {
                $verification = [pscustomobject]@{ Ok = $false; Error = 'ISO verification job returned no output.'; Architecture = ''; Editions = @() }
            }
            Remove-Job -Job $slot.Job -Force -ErrorAction SilentlyContinue
            $slot.Job = $null

            if (Get-Command Clear-WinMintUiIsoMountJournal -ErrorAction SilentlyContinue) {
                Clear-WinMintUiIsoMountJournal
            }

            if ($verification.Ok) {
                $uiState.Iso.State = [WinMintIsoState]::Verified
                $uiState.Iso.Error = ''
                $uiState.Iso.Architecture = [string]$verification.Architecture
                $uiState.Iso.Editions = @($verification.Editions)
            } else {
                $uiState.Iso.State = [WinMintIsoState]::Error
                $uiState.Iso.Error = [string]$verification.Error
                $uiState.Iso.Architecture = ''
                $uiState.Iso.Editions = @()
            }

            Sync-WinMintUiIsoControls -State $uiState
        }
        if (-not $ok) {
            try { $poll.Stop() } catch {}
            try { Stop-WinMintUiIsoVerification } catch {}
        }
    })
    $iv.DispatcherPoll.Start()
}

function Invoke-WinMintUiBrowseIso {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][System.Windows.Window]$Window
    )

    $dialog = [Microsoft.Win32.OpenFileDialog]::new()
    $dialog.Title = 'Select Windows 11 ISO'
    $dialog.Filter = 'ISO files (*.iso)|*.iso|All files (*.*)|*.*'
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false

    if ($dialog.ShowDialog($Window)) {
        Set-WinMintUiIsoPath -State $State -Path $dialog.FileName
        Start-WinMintUiIsoVerification -State $State -Window $Window
    }
}

function Invoke-WinMintUiClipboardIsoImport {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][System.Windows.Window]$Window
    )

    $ctx = Get-WinMintUiAppContextOptional
    if ($null -ne $ctx -and [bool]$ctx.FixtureMode) { return }
    try {
        if (-not [System.Windows.Clipboard]::ContainsFileDropList()) { return }
        $drops = [System.Windows.Clipboard]::GetFileDropList()
        foreach ($drop in $drops) {
            $path = [string]$drop
            if ($path.EndsWith('.iso', [System.StringComparison]::OrdinalIgnoreCase) -and
                (Test-Path -LiteralPath $path)) {
                if ($path -eq [string]$State.Iso.Path -and
                    ([WinMintIsoState]$State.Iso.State) -in @([WinMintIsoState]::Verified, [WinMintIsoState]::Verifying)) {
                    return
                }
                Set-WinMintUiIsoPath -State $State -Path $path
                Start-WinMintUiIsoVerification -State $State -Window $Window
                return
            }
        }
    } catch {}
}
