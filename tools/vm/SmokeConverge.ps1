#requires -Version 7.6
Set-StrictMode -Version Latest

function Resolve-SmokePhase {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('apply', 'wait', 'assert', 'green', 'failed')]
        [string] $HostStage,
        [string] $VmState,
        [long] $VhdFileSizeBytes = 0,
        [switch] $HeartbeatOk,
        [switch] $EvidenceReady
    )
    switch ($HostStage) {
        'apply' { return 'apply' }
        'assert' { return 'assert' }
        'green' { return 'green' }
        'failed' { return 'failed' }
    }
    if ($VmState -notin @('Running')) { return 'setup-reboot' }
    if ($HeartbeatOk) { return 'guest-up' }
    if ($VhdFileSizeBytes -ge 1GB) { return 'winpe-apply' }
    return 'vm-boot'
}

function Get-SmokeVmStartupBytes {
    # 8GB is apply/OOBE headroom; 4GB is only the Win11 floor.
    8GB
}

function Get-SmokePreferDiskBootDecision {
    param(
        [bool] $AlreadyPreferred,
        [bool] $VhdHasImage
    )
    if ($AlreadyPreferred) { return 'skip' }
    # ponytail: ejecting here races WinPE wpeutil reboot → Boot Manager 0xc0000178 STATUS_NO_MEDIA.
    if (-not $VhdHasImage) { return 'keep-dvd' }
    return 'prefer-hdd'
}

function Get-SmokeEjectDvdDecision {
    param(
        [bool] $AlreadyEjected,
        [bool] $DiskBootPreferred,
        [bool] $HeartbeatOk
    )
    if ($AlreadyEjected -or -not $DiskBootPreferred -or -not $HeartbeatOk) { return 'skip' }
    return 'eject'
}

function Get-SmokeRunIdStampDecision {
    <#
    .SYNOPSIS
      Whether the wait loop should try PS Direct stamp of smoke-run.id this poll.
    #>
    param(
        [bool] $AlreadyStamped,
        [bool] $HeartbeatOk
    )
    if ($AlreadyStamped) { return 'skip' }
    if (-not $HeartbeatOk) { return 'skip' }
    return 'try-stamp'
}

function Write-SmokeRunIdFile {
    <#
    .SYNOPSIS
      Write smoke-run.id bytes (UTF-8 no BOM, no trailing newline).
    .NOTES
      Guest PSD runs Windows PowerShell 5.1 — Set-Content -Encoding + -NoNewline is a
      parameter-set clash there. Keep this path as WriteAllText only.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Path,
        [Parameter(Mandatory)]
        [string] $RunId
    )
    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $RunId.Trim(), [System.Text.UTF8Encoding]::new($false))
}

function Get-SmokeNicAttachAtCreateDecision {
    <#
    .SYNOPSIS
      Whether Smoke connects Default Switch before Start-VM.
      Offline OOBE (default) defers NAT until Supervisor to skip ZDP during OOBE.
    #>
    param([bool] $OnlineOobe = $false)
    if ($OnlineOobe) { return 'connect' }
    return 'defer'
}

function Get-SmokeNicReconnectDecision {
    <#
    .SYNOPSIS
      Whether the wait loop should attach Default Switch this poll.
      Offline OOBE: prefer Supervisor sighted. Bare guest-up heartbeat often lands on
      CloudExperienceHost "Just a moment" — connecting NAT there re-enables ZDP.
      Fallback: connect only after guest-up has been sticky long enough for HideWireless
      OOBE to finish offline (GuestUpNicDeferSeconds).
    #>
    param(
        [bool] $OnlineOobe = $false,
        [bool] $AlreadyConnected = $false,
        [bool] $SupervisorRunning = $false,
        [bool] $GuestUpSticky = $false,
        [int] $GuestUpStickySeconds = 0,
        # ponytail: 6m covers typical HideWireless OOBE after heartbeat; ceiling = ZDP if too low.
        [int] $GuestUpNicDeferSeconds = 360
    )
    if ($OnlineOobe -or $AlreadyConnected) { return 'skip' }
    if ($SupervisorRunning) { return 'connect' }
    if ($GuestUpSticky -and $GuestUpStickySeconds -ge $GuestUpNicDeferSeconds) { return 'connect' }
    return 'hold'
}

function New-SmokeOfflineOobeProfile {
    <#
    .SYNOPSIS
      Copy a Profile with requireWifiDuringOobe=false for offline-OOBE Apply.
      Rewrites passwordPath to a fully-qualified path so the overlay can live under Work.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $SourceProfilePath,
        [Parameter(Mandatory)]
        [string] $DestPath
    )
    if (-not (Test-Path -LiteralPath $SourceProfilePath -PathType Leaf)) {
        throw "Source Profile not found: $SourceProfilePath"
    }
    $srcFull = (Resolve-Path -LiteralPath $SourceProfilePath).Path
    $doc = Get-Content -LiteralPath $srcFull -Raw -Encoding utf8 | ConvertFrom-Json
    if ($null -eq $doc.account) {
        throw "Profile has no account block: $srcFull"
    }
    $doc.account | Add-Member -NotePropertyName requireWifiDuringOobe -NotePropertyValue $false -Force
    $names = @($doc.account.PSObject.Properties.Name)
    if ($names -contains 'passwordPath' -and -not [string]::IsNullOrWhiteSpace([string]$doc.account.passwordPath)) {
        $authored = [string]$doc.account.passwordPath
        if (-not [IO.Path]::IsPathFullyQualified($authored)) {
            $resolved = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $srcFull) $authored))
            $doc.account.passwordPath = $resolved
        }
    }
    $destDir = Split-Path -Parent $DestPath
    if (-not [string]::IsNullOrWhiteSpace($destDir)) {
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    }
    $json = $doc | ConvertTo-Json -Depth 40
    [System.IO.File]::WriteAllText($DestPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    return $DestPath
}

function Resolve-WinMintSmokeGuestCredential {
    <#
    .SYNOPSIS
      PS Direct credential from a Profile: account.password, else account.passwordPath
      resolved relative to the Profile's directory (mirrors ProfileFile.TryLoad).
    .NOTES
      Throws when a localAutoLogon Profile yields no credential — New-PSSession -VMName
      has a mandatory -Credential and would block the wait loop on an interactive prompt.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $ProfilePath
    )
    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
        throw "Profile not found: $ProfilePath"
    }
    $doc = Get-Content -LiteralPath $ProfilePath -Raw -Encoding utf8 | ConvertFrom-Json
    $account = if ($doc.PSObject.Properties.Name -contains 'account') { $doc.account } else { $null }
    if ($null -eq $account) {
        throw "Profile has no account block: $ProfilePath"
    }
    $names = @($account.PSObject.Properties.Name)
    $username = if ($names -contains 'username') { [string]$account.username } else { '' }
    if ([string]::IsNullOrWhiteSpace($username)) {
        throw "Profile account.username missing: $ProfilePath"
    }
    $password = if ($names -contains 'password') { [string]$account.password } else { '' }
    if ([string]::IsNullOrWhiteSpace($password)) {
        $authored = if ($names -contains 'passwordPath') { [string]$account.passwordPath } else { '' }
        if ([string]::IsNullOrWhiteSpace($authored)) {
            throw ("Profile '$ProfilePath' has neither account.password nor account.passwordPath — " +
                'PS Direct needs guest credentials for the Smoke wait loop.')
        }
        $resolved = $authored
        if (-not [IO.Path]::IsPathFullyQualified($authored)) {
            if ([IO.Path]::IsPathRooted($authored)) {
                throw "account.passwordPath '$authored' is root-relative — use fully qualified or Profile-relative."
            }
            $profileDir = Split-Path -Parent (Resolve-Path -LiteralPath $ProfilePath).Path
            $resolved = [IO.Path]::GetFullPath((Join-Path $profileDir $authored))
        }
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            throw "account.passwordPath '$authored' resolves to missing file: $resolved"
        }
        $password = ([IO.File]::ReadAllText($resolved)).TrimEnd("`r", "`n")
        if ([string]::IsNullOrEmpty($password)) {
            throw "Password file is empty: $resolved"
        }
    }
    return [pscredential]::new($username, (ConvertTo-SecureString $password -AsPlainText -Force))
}

function Get-SmokeStallExtendDecision {
    <#
    .SYNOPSIS
      Whether this poll extends the stall budget.
      Pre-guest-up: CPU activity or setup reboot churn counts (WinPE/OOBE leave no durable
      guest signal). After sticky guest-up: only real guest progress extends — Supervisor
      process alive (its own wall clock bounds tenure) or new evidence bytes. A CPU-burning
      CloudExperienceHost "Just a moment" spinner no longer resets stall. Transient PS
      Direct transport errors after guest-up extend (grace) so flake does not immediately
      fail-close as STALL_SUSPECT; chronic flake still hits wall clock.
    #>
    param(
        [string] $VmState,
        [int] $Cpu = 0,
        [bool] $GuestUpSticky = $false,
        [bool] $GuestProgress = $false,
        [bool] $ProbeTransportError = $false
    )
    if ($VmState -in @('Starting', 'Stopping')) { return 'extend' }
    if ($GuestUpSticky) {
        if ($GuestProgress) { return 'extend' }
        if ($ProbeTransportError) { return 'extend' }
        return 'hold'
    }
    if ($Cpu -gt 0) { return 'extend' }
    return 'hold'
}

function Get-SmokeStallFailVerdict {
    <#
    .SYNOPSIS
      Named stall fail reason after the stall budget is exhausted (guest-up phase only).
    #>
    param(
        [bool] $GuestUpSticky = $false,
        [bool] $HandoffIncomplete = $false,
        [bool] $ProbeTransportError = $false
    )
    if (-not $GuestUpSticky) { return 'stall-suspect' }
    if ($HandoffIncomplete) { return 'handoff-stuck' }
    if ($ProbeTransportError) { return 'psd-flake' }
    return 'stall-suspect'
}

function Get-SmokeSetupRebootTransition {
    <#
    .SYNOPSIS
      Counts a setup reboot when the VM leaves Running after the VHD carries an applied
      image. Pre-image transitions are WinPE/firmware churn, not setup reboots.
    #>
    param(
        [string] $LastVmState,
        [string] $VmState,
        [bool] $VhdHasImage
    )
    if ($LastVmState -eq 'Running' -and $VmState -in @('Stopping', 'Off') -and $VhdHasImage) {
        return 'count'
    }
    return 'skip'
}

function Get-SmokeRebootLoopVerdict {
    <#
    .SYNOPSIS
      Fail fast on a boot loop instead of churning until wall clock: setup reboots past
      the cap are a loop, not progress (each reboot also burns one guest autologon).
    #>
    param(
        [int] $SetupRebootCount = 0,
        [int] $MaxSetupReboots = 8
    )
    if ($MaxSetupReboots -gt 0 -and $SetupRebootCount -gt $MaxSetupReboots) {
        return 'reboot-loop'
    }
    return 'continue'
}

function Get-SmokeGuestProgressDecision {
    <#
    .SYNOPSIS
      After sticky guest-up, stall extends only on Supervisor alive or new evidence bytes.
    #>
    param(
        [string] $LastFingerprint = '',
        [string] $Fingerprint = '',
        [bool] $SupervisorRunning = $false
    )
    if ($SupervisorRunning) { return 'progress' }
    if (-not [string]::IsNullOrWhiteSpace($Fingerprint) -and $Fingerprint -ne $LastFingerprint) {
        return 'progress'
    }
    return 'idle'
}

function Get-SmokeNudgeRearmDecision {
    <#
    .SYNOPSIS
      Re-arm the DVD boot-key window on return to Running from any non-Running
      state while DVD is still first (Off→Starting→Running is the usual pair).
    #>
    param(
        [string] $LastVmState,
        [string] $VmState,
        [bool] $DiskBootPreferred
    )
    if ($DiskBootPreferred) { return 'skip' }
    if ($VmState -eq 'Running' -and $LastVmState -and $LastVmState -ne 'Running') { return 'rearm' }
    return 'skip'
}

function Get-SmokeSuspendVmDecision {
    <#
    .SYNOPSIS
      After a Smoke fail: freeze WinPE/setup consoles, ACPI-stop a Windows guest,
      leave Apply fails alone (VM may not exist yet).
      ACPI Stop-VM (not TurnOff) so leftover Windows is not DirtyShutdown —
      Hyper-V Turn Off is a power-cut and the next Start is "Why did my PC restart?".
    #>
    param([string] $FailureMessage)
    if ($FailureMessage -match 'Apply failed') { return 'skip' }
    if ($FailureMessage -match '^(STALL_SUSPECT|PSD_FLAKE|HANDOFF_STUCK|EMPTY_VHD|REBOOT_LOOP|Wall clock)') {
        return 'suspend'
    }
    return 'shutdown'
}

function Get-SmokeWatcherSpawnDecision {
    param([bool] $MarkerPidAlive)
    if ($MarkerPidAlive) { return 'skip' }
    return 'spawn'
}

function Get-SmokeWaitPhaseSticky {
    <#
    .SYNOPSIS
      Wait-phase resolution with sticky guest-up after two consecutive heartbeat OK polls.
      Clears sticky when VM is not Running. DVD eject must still use live heartbeat.
    #>
    param(
        [string] $VmState,
        [long] $VhdFileSizeBytes = 0,
        [switch] $HeartbeatOk,
        [bool] $GuestUpSticky = $false,
        [int] $ConsecutiveHeartbeatOk = 0
    )
    if ($VmState -notin @('Running')) {
        return [pscustomobject]@{
            Phase                   = (Resolve-SmokePhase -HostStage wait -VmState $VmState -VhdFileSizeBytes $VhdFileSizeBytes -HeartbeatOk:$HeartbeatOk)
            GuestUpSticky           = $false
            ConsecutiveHeartbeatOk  = 0
        }
    }

    $consec = if ($HeartbeatOk) { [math]::Max(0, $ConsecutiveHeartbeatOk) + 1 } else { 0 }
    $sticky = $GuestUpSticky -or ($consec -ge 2)
    if ($sticky) {
        return [pscustomobject]@{
            Phase                  = 'guest-up'
            GuestUpSticky          = $true
            ConsecutiveHeartbeatOk = $consec
        }
    }

    return [pscustomobject]@{
        Phase                  = (Resolve-SmokePhase -HostStage wait -VmState $VmState `
                -VhdFileSizeBytes $VhdFileSizeBytes -HeartbeatOk:$HeartbeatOk)
        GuestUpSticky          = $false
        ConsecutiveHeartbeatOk = $consec
    }
}

function Get-SmokeWaitTick {
    <#
    .SYNOPSIS
      One Smoke wait poll: snapshot in, actions out. Pure — no Hyper-V.
    #>
    param([Parameter(Mandatory)] $Snap)

    $d = @{
        VmState                   = ''
        LastVmState               = ''
        Cpu                       = 0
        VhdFileSizeBytes          = 0L
        VhdHasImage               = $null
        HeartbeatOk               = $false
        GuestUpSticky             = $false
        ConsecutiveHeartbeatOk    = 0
        DiskBootPreferred         = $false
        DvdEjected                = $false
        SmokeRunIdStamped         = $false
        LastFingerprint           = ''
        Fingerprint               = ''
        SupervisorRunning         = $false
        ProbeTransportError       = $false
        HandoffIncomplete         = $false
        SetupRebootCount          = 0
        MaxSetupReboots           = 8
        StallElapsedMinutes       = 0.0
        StallMinutes              = 45
        EmptyVhdRunningSeconds    = 0
        EmptyVhdFailAfterSeconds  = 480
        NudgeElapsedMinutes       = 0.0
        HalfStallShot             = $false
    }
    foreach ($p in $Snap.PSObject.Properties) {
        $d[$p.Name] = $p.Value
    }

    $vmState = [string]$d.VmState
    $vhdBytes = [long]$d.VhdFileSizeBytes
    $vhdHasImage = if ($null -ne $d.VhdHasImage) { [bool]$d.VhdHasImage } else { $vhdBytes -ge 1GB }
    $hb = [bool]$d.HeartbeatOk
    $diskPreferred = [bool]$d.DiskBootPreferred

    if ($vmState -notin @('Running', 'Starting', 'Stopping', 'Off')) {
        return [pscustomobject]@{
            Phase                  = 'setup-reboot'
            GuestUpSticky          = $false
            ConsecutiveHeartbeatOk = 0
            SetupRebootCount       = [int]$d.SetupRebootCount
            LastFingerprint        = [string]$d.LastFingerprint
            PreferDisk             = 'skip'
            EjectDvd               = 'skip'
            StartVm                = $false
            RearmNudge             = $false
            ExtendStall            = $false
            TryStamp               = $false
            SendNudge              = $false
            HalfStallShot          = $false
            HostLine               = "VM $vmState"
            FailReason             = 'UNEXPECTED'
            FailMessage            = "VM in unexpected state: $vmState"
        }
    }

    $considerPrefer = $vmState -in @('Running', 'Stopping', 'Off')
    $preferDisk = if ($considerPrefer) {
        Get-SmokePreferDiskBootDecision -AlreadyPreferred $diskPreferred -VhdHasImage $vhdHasImage
    }
    else {
        'skip'
    }
    $diskAfter = $diskPreferred -or ($preferDisk -eq 'prefer-hdd')
    $ejectDvd = if ($vmState -eq 'Running') {
        Get-SmokeEjectDvdDecision -AlreadyEjected ([bool]$d.DvdEjected) `
            -DiskBootPreferred $diskAfter -HeartbeatOk $hb
    }
    else {
        'skip'
    }

    $setupCount = [int]$d.SetupRebootCount
    if ((Get-SmokeSetupRebootTransition -LastVmState ([string]$d.LastVmState) `
            -VmState $vmState -VhdHasImage $vhdHasImage) -eq 'count') {
        $setupCount++
    }

    $rearmNudge = (Get-SmokeNudgeRearmDecision -LastVmState ([string]$d.LastVmState) `
            -VmState $vmState -DiskBootPreferred $diskAfter) -eq 'rearm'
    $nudgeElapsed = [double]$d.NudgeElapsedMinutes
    if ($rearmNudge) { $nudgeElapsed = 0 }

    $guestProgress = (Get-SmokeGuestProgressDecision -LastFingerprint ([string]$d.LastFingerprint) `
            -Fingerprint ([string]$d.Fingerprint) -SupervisorRunning ([bool]$d.SupervisorRunning)) -eq 'progress'
    $lastFp = [string]$d.LastFingerprint
    if ($guestProgress) { $lastFp = [string]$d.Fingerprint }

    $probeTransportError = [bool]$d.ProbeTransportError
    $handoffIncomplete = [bool]$d.HandoffIncomplete
    $extendStall = (Get-SmokeStallExtendDecision -VmState $vmState -Cpu ([int]$d.Cpu) `
            -GuestUpSticky ([bool]$d.GuestUpSticky) -GuestProgress $guestProgress `
            -ProbeTransportError $probeTransportError) -eq 'extend'
    $stallElapsedInput = [double]$d.StallElapsedMinutes
    $stallElapsed = $stallElapsedInput
    if ($extendStall) { $stallElapsed = 0 }

    $tryStamp = (Get-SmokeRunIdStampDecision -AlreadyStamped ([bool]$d.SmokeRunIdStamped) `
            -HeartbeatOk $hb) -eq 'try-stamp'

    $phaseRes = Get-SmokeWaitPhaseSticky -VmState $vmState -VhdFileSizeBytes $vhdBytes `
        -HeartbeatOk:$hb -GuestUpSticky ([bool]$d.GuestUpSticky) `
        -ConsecutiveHeartbeatOk ([int]$d.ConsecutiveHeartbeatOk)
    $phase = [string]$phaseRes.Phase
    $vhdMb = [int][math]::Round($vhdBytes / 1MB)
    $failReason = $null
    $failMessage = $null
    $watch = Get-SmokeWatchVerdict -Phase $phase -VmState $vmState -VhdFileSizeMB $vhdMb `
        -EmptyVhdRunningSeconds ([int]$d.EmptyVhdRunningSeconds) `
        -EmptyVhdFailAfterSeconds ([int]$d.EmptyVhdFailAfterSeconds)
    $emptyMin = [int]([int]$d.EmptyVhdFailAfterSeconds / 60)
    if ($watch -eq 'empty-vhd') {
        $failReason = 'EMPTY_VHD'
        $failMessage = "EMPTY_VHD: WinPE has not applied (VHD FileSize still under 1GB) for ${emptyMin} minutes after Running."
    }
    elseif ((Get-SmokeRebootLoopVerdict -SetupRebootCount $setupCount `
            -MaxSetupReboots ([int]$d.MaxSetupReboots)) -eq 'reboot-loop') {
        $failReason = 'REBOOT_LOOP'
        $failMessage = "REBOOT_LOOP: $setupCount setup reboots after the image applied (cap $([int]$d.MaxSetupReboots))."
    }
    else {
        $stallMin = [int]$d.StallMinutes
        if ($stallElapsedInput -ge $stallMin -and -not $extendStall) {
            switch ((Get-SmokeStallFailVerdict -GuestUpSticky ([bool]$d.GuestUpSticky) `
                    -HandoffIncomplete $handoffIncomplete -ProbeTransportError $probeTransportError)) {
                'handoff-stuck' {
                    $failReason = 'HANDOFF'
                    $failMessage = "HANDOFF_STUCK: Complete evidence but shell/explorer handoff not verified for ${stallMin} minutes."
                }
                'psd-flake' {
                    $failReason = 'PSD_FLAKE'
                    $failMessage = "PSD_FLAKE: PS Direct transport errors with no guest progress for ${stallMin} minutes (fail-fast before WallClockTimeout)."
                }
                default {
                    $failReason = 'STALL'
                    $failMessage = "STALL_SUSPECT: no guest progress for ${stallMin} minutes (fail-fast before WallClockTimeout)."
                }
            }
        }
    }

    $hostLine = switch ($vmState) {
        'Starting' { 'VM Starting (setup reboot)…' }
        'Stopping' { 'VM Stopping (setup reboot)…' }
        'Off' { 'VM Off during setup — starting again…' }
        default { "VM $vmState" }
    }

    return [pscustomobject]@{
        Phase                  = $phase
        GuestUpSticky          = [bool]$phaseRes.GuestUpSticky
        ConsecutiveHeartbeatOk = [int]$phaseRes.ConsecutiveHeartbeatOk
        SetupRebootCount       = $setupCount
        LastFingerprint        = $lastFp
        PreferDisk             = $preferDisk
        EjectDvd               = $ejectDvd
        StartVm                = ($vmState -eq 'Off')
        RearmNudge             = $rearmNudge
        ExtendStall            = $extendStall
        TryStamp               = $tryStamp
        SendNudge              = (-not $diskAfter -and $nudgeElapsed -lt 3 -and $vmState -eq 'Running')
        HalfStallShot          = (-not [bool]$d.HalfStallShot -and $stallElapsed -ge ([int]$d.StallMinutes / 2.0))
        HostLine               = $hostLine
        FailReason             = $failReason
        FailMessage            = $failMessage
    }
}

$Script:WinMintExplorerShell = 'explorer.exe'
$Script:WinMintSupervisorProcessName = 'Supervisor'

function Test-WinMintExplorerShellValue {
    param([AllowEmptyString()] [string] $Shell)
    if ([string]::IsNullOrWhiteSpace($Shell)) { return $false }
    $trim = $Shell.Trim()
    return $trim.Equals($Script:WinMintExplorerShell, [System.StringComparison]::OrdinalIgnoreCase) `
        -or $trim.EndsWith("\$($Script:WinMintExplorerShell)", [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-WinMintGuestEvidenceRows {
    param(
        [Parameter(Mandatory)] [string] $Directory,
        [string] $RequiredSmokeRunId = ''
    )
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return @()
    }
    return @(
        Get-ChildItem -LiteralPath $Directory -Filter 'evidence-*.json' -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                try {
                    $doc = Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8 | ConvertFrom-Json
                    if (-not [string]::IsNullOrWhiteSpace($RequiredSmokeRunId)) {
                        $got = ''
                        if ($doc.PSObject.Properties.Name -contains 'smokeRunId') {
                            $got = [string]$doc.smokeRunId
                        }
                        if ($got -ne $RequiredSmokeRunId) { return }
                    }
                    [pscustomobject]@{
                        Path    = $_.FullName
                        Outcome = [string]$doc.outcome
                        SortKey = if ($_.Name -match '^evidence-(\d+)') { [long]$Matches[1] } else { 0L }
                    }
                }
                catch {
                    $null
                }
            } |
            Where-Object { $null -ne $_ }
    )
}

function Select-WinMintGuestEvidencePath {
    param(
        [Parameter(Mandatory)] [string] $Directory,
        [string] $RequiredSmokeRunId = ''
    )
    $rows = @(Get-WinMintGuestEvidenceRows -Directory $Directory -RequiredSmokeRunId $RequiredSmokeRunId)
    if ($rows.Count -eq 0) { return $null }
    $failed = @($rows | Where-Object { $_.Outcome -eq 'Failed' } | Sort-Object SortKey -Descending)
    if ($failed.Count -ge 1) { return [string]$failed[0].Path }
    $complete = @($rows | Where-Object { $_.Outcome -eq 'Complete' } | Sort-Object SortKey -Descending)
    if ($complete.Count -ge 1) { return [string]$complete[0].Path }
    # Reboot is not terminal — still select so readiness can return wait-reboot.
    $reboot = @($rows | Where-Object { $_.Outcome -eq 'Reboot' } | Sort-Object SortKey -Descending)
    if ($reboot.Count -ge 1) { return [string]$reboot[0].Path }
    return $null
}

function Get-WinMintGuestHandoffReadiness {
    <#
    .SYNOPSIS
      Pure guest snap → ready | wait-reboot | wait-handoff | failed.
      PS Direct only materializes the snap; Assert shares these readiness facts.
      ExplorerRunning: live probes pass $true/$false (explorer.exe process alive — a
      restored Shell value with a crashed explorer is not a desktop); static fixtures
      omit it ($null = neutral).
    #>
    param(
        [Parameter(Mandatory)] $EvidenceDoc,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $LiveShell,
        [bool] $SupervisorRunning = $false,
        [string] $RequiredSmokeRunId = '',
        $ExplorerRunning = $null
    )
    $outcome = [string]$EvidenceDoc.outcome
    if ($outcome -eq 'Failed') { return 'failed' }
    if ($outcome -eq 'Reboot') { return 'wait-reboot' }
    if ($outcome -ne 'Complete') { return 'wait-handoff' }

    if (-not [string]::IsNullOrWhiteSpace($RequiredSmokeRunId)) {
        $got = ''
        if ($EvidenceDoc.PSObject.Properties.Name -contains 'smokeRunId') {
            $got = [string]$EvidenceDoc.smokeRunId
        }
        if ($got -ne $RequiredSmokeRunId) { return 'wait-handoff' }
    }
    if ([string]$EvidenceDoc.statusCode -ne 'jobs.ok') { return 'wait-handoff' }
    $phases = @($EvidenceDoc.phases)
    if ($phases -notcontains 'jobs.ok') { return 'wait-handoff' }
    if ($phases -notcontains 'oobe.dismiss') { return 'wait-handoff' }
    if (-not (Test-WinMintExplorerShellValue $LiveShell)) { return 'wait-handoff' }
    if ($SupervisorRunning) { return 'wait-handoff' }
    if ($ExplorerRunning -is [bool] -and -not $ExplorerRunning) { return 'wait-handoff' }
    return 'ready'
}

function Test-WinMintGuestEvidenceTerminal {
    <#
      Fail-closed S4 gate via Get-WinMintGuestHandoffReadiness: ready or failed stop the wait.
    #>
    param(
        [Parameter(Mandatory)] $EvidenceDoc,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $LiveShell,
        [bool] $SupervisorRunning = $false,
        [string] $RequiredSmokeRunId = '',
        $ExplorerRunning = $null
    )
    $verdict = Get-WinMintGuestHandoffReadiness -EvidenceDoc $EvidenceDoc -LiveShell $LiveShell `
        -SupervisorRunning:$SupervisorRunning -RequiredSmokeRunId $RequiredSmokeRunId `
        -ExplorerRunning $ExplorerRunning
    return $verdict -in @('ready', 'failed')
}
