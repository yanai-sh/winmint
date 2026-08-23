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

function Write-SmokeStatus {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Phase,
        [Parameter(Mandatory)][string] $VmName,
        $VmState = $null,
        $Cpu = $null,
        $Heartbeat = $null,
        $VhdFileSizeMB = $null,
        [int] $StallMinutesLeft = 0,
        [int] $WallMinutesLeft = 0,
        [string] $LastHostLine = '',
        $OutputIso = $null,
        [int] $WaiterPid = 0,
        [string] $RunId = '',
        [int] $SetupRebootCount = 0
    )
    try {
        $dir = Split-Path -Parent $Path
        if ($dir) { New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null }
        if ($WaiterPid -le 0) { $WaiterPid = [int]$PID }
        $doc = [ordered]@{
            schemaVersion    = 'winmint.smoke.status/v1'
            updatedAt        = [datetime]::UtcNow.ToString('o')
            runId            = $RunId
            phase            = $Phase
            vmName           = $VmName
            vmState          = $VmState
            cpu              = $Cpu
            heartbeat        = $Heartbeat
            vhdFileSizeMB    = $VhdFileSizeMB
            stallMinutesLeft = $StallMinutesLeft
            wallMinutesLeft  = $WallMinutesLeft
            lastHostLine     = $LastHostLine
            outputIso        = $OutputIso
            waiterPid         = $WaiterPid
            setupRebootCount  = $SetupRebootCount
        }
        ($doc | ConvertTo-Json -Compress) | Set-Content -LiteralPath $Path -Encoding utf8 -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not write Smoke status: $($_.Exception.Message)"
    }
}

function Start-SmokeMonitor {
    param(
        [Parameter(Mandatory)][string] $VmName,
        [string] $ConnectExe = (Join-Path $env:WINDIR 'System32\vmconnect.exe'),
        [scriptblock] $Launcher = {
            param($Exe, $Name)
            Start-Process -FilePath $Exe -ArgumentList @('localhost', $Name)
        }
    )
    if (-not (Test-Path -LiteralPath $ConnectExe)) {
        Write-Warning "vmconnect.exe not found; continuing headless"
        return
    }
    try {
        & $Launcher $ConnectExe $VmName
    }
    catch {
        Write-Warning "Could not start VMConnect: $($_.Exception.Message)"
    }
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
            throw "account.passwordPath '$authored' resolves to missing file: $resolved (docs/design/SECRETS.md)"
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
      CloudExperienceHost "Just a moment" spinner no longer resets stall.
    #>
    param(
        [string] $VmState,
        [int] $Cpu = 0,
        [bool] $GuestUpSticky = $false,
        [bool] $GuestProgress = $false
    )
    if ($VmState -in @('Starting', 'Stopping')) { return 'extend' }
    if ($GuestUpSticky) {
        if ($GuestProgress) { return 'extend' }
        return 'hold'
    }
    if ($Cpu -gt 0) { return 'extend' }
    return 'hold'
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
      Freeze the console on stall/wall/reboot-loop so VMConnect can inspect later.
      Apply failures leave the VM alone (it may not exist yet).
    #>
    param([string] $FailureMessage)
    if ($FailureMessage -match '^(STALL_SUSPECT|EMPTY_VHD|REBOOT_LOOP|Wall clock)') {
        return 'suspend'
    }
    return 'skip'
}

function Get-SmokeWatcherSpawnDecision {
    param([bool] $MarkerPidAlive)
    if ($MarkerPidAlive) { return 'skip' }
    return 'spawn'
}

function ConvertTo-WinMintBmp565 {
    <#
    .SYNOPSIS
      Wrap a raw RGB565 pixel buffer (Msvm thumbnail wire format) as a top-down 16bpp
      BI_BITFIELDS BMP. Pure — no Hyper-V.
    #>
    param(
        [Parameter(Mandatory)] [byte[]] $PixelData,
        [Parameter(Mandatory)] [int] $Width,
        [Parameter(Mandatory)] [int] $Height
    )
    $stride = $Width * 2
    if ($stride % 4 -ne 0) {
        throw "ConvertTo-WinMintBmp565 needs a 4-byte-aligned row (width $Width is not)"
    }
    if ($PixelData.Length -ne ($stride * $Height)) {
        throw "pixel buffer $($PixelData.Length) bytes != ${Width}x${Height}x2"
    }
    $headerSize = 14 + 40 + 12
    $ms = [IO.MemoryStream]::new()
    $bw = [IO.BinaryWriter]::new($ms)
    try {
        $bw.Write([byte]0x42); $bw.Write([byte]0x4D)          # 'BM'
        $bw.Write([int]($headerSize + $PixelData.Length))     # file size
        $bw.Write([int]0)                                     # reserved
        $bw.Write([int]$headerSize)                           # pixel offset
        $bw.Write([int]40)                                    # BITMAPINFOHEADER size
        $bw.Write([int]$Width)
        $bw.Write([int](-$Height))                            # negative height = top-down rows
        $bw.Write([int16]1)                                   # planes
        $bw.Write([int16]16)                                  # bpp
        $bw.Write([int]3)                                     # BI_BITFIELDS
        $bw.Write([int]$PixelData.Length)
        $bw.Write([int]2835); $bw.Write([int]2835)            # 72 DPI
        $bw.Write([int]0); $bw.Write([int]0)                  # palette
        $bw.Write([int]0xF800); $bw.Write([int]0x07E0); $bw.Write([int]0x001F)
        $bw.Write($PixelData)
        $bw.Flush()
        return , $ms.ToArray()
    }
    finally {
        $bw.Dispose()
        $ms.Dispose()
    }
}

function Save-SmokeVmScreenshot {
    <#
    .SYNOPSIS
      Best-effort VM console screenshot for post-mortem (which screen was the guest on?).
      Diagnostics only — never an acceptance input (witnessed-smoke spec).
    #>
    param(
        [Parameter(Mandatory)] [string] $VmName,
        [Parameter(Mandatory)] [string] $Path,
        [int] $Width = 640,
        [int] $Height = 480
    )
    try {
        $vmCs = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem `
            -Filter "ElementName='$VmName'" -ErrorAction Stop
        if ($null -eq $vmCs) { return $false }
        $svc = Get-CimInstance -Namespace root\virtualization\v2 `
            -ClassName Msvm_VirtualSystemManagementService -ErrorAction Stop
        $result = Invoke-CimMethod -InputObject $svc -MethodName GetVirtualSystemThumbnailImage -Arguments @{
            HeightPixels = [uint16]$Height
            WidthPixels  = [uint16]$Width
            TargetSystem = $vmCs
        }
        if ($null -eq $result -or $result.ReturnValue -ne 0 -or -not $result.ImageData) { return $false }
        $dir = Split-Path -Parent $Path
        if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $bmp = ConvertTo-WinMintBmp565 -PixelData ([byte[]]$result.ImageData) -Width $Width -Height $Height
        [IO.File]::WriteAllBytes($Path, $bmp)
        Write-Host "VM console screenshot → $Path"
        return $true
    }
    catch {
        Write-Warning "Could not capture VM console screenshot: $($_.Exception.Message)"
        return $false
    }
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

function Get-SmokeWatchVerdict {
    <#
    .SYNOPSIS
      Watch-only verdict from Hyper-V-native signals + status freshness. Never infers death from PIDs.
    .NOTES
      Invoke-Smoke throws on empty-vhd. Watchers must not Stop-VM / Remove-VM;
      harness-stale stays watch-only.
      External watchers pass -PriorRunId (runId of any status present at watch
      start; empty when none) so a carried-over terminal status reads as
      awaiting-run, never done. Invoke-Smoke's own wait loop omits it.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Phase,
        [string] $VmState = '',
        [int] $VhdFileSizeMB = 0,
        [int] $StatusAgeSeconds = 0,
        [int] $EmptyVhdRunningSeconds = 0,
        [int] $EmptyVhdFailAfterSeconds = 480,
        [int] $HarnessStaleAfterSeconds = 120,
        [string] $StatusRunId = '',
        [string] $PriorRunId = ''
    )
    # Run identity first: a status left by a prior run must never be this run's outcome.
    if ($PSBoundParameters.ContainsKey('PriorRunId') -and $StatusRunId -eq $PriorRunId) {
        return 'awaiting-run'
    }
    if ($Phase -in @('green', 'failed', 'assert')) {
        return 'done'
    }
    # DISM Apply can run for hours without a status refresh.
    if ($Phase -eq 'apply') {
        return 'continue'
    }
    if ($VmState -eq 'Running' -and $VhdFileSizeMB -lt 1024 -and
        $EmptyVhdRunningSeconds -ge $EmptyVhdFailAfterSeconds) {
        return 'empty-vhd'
    }
    if ($StatusAgeSeconds -gt $HarnessStaleAfterSeconds) {
        return 'harness-stale'
    }
    return 'continue'
}

function Get-WinMintApplyHostFailure {
    param([Parameter(Mandatory)] [string] $WorkDirectory)
    $applyStatusPath = Join-Path $WorkDirectory 'apply-status.txt'
    if (-not (Test-Path -LiteralPath $applyStatusPath -PathType Leaf)) {
        return $null
    }
    $applyStatus = Get-Content -LiteralPath $applyStatusPath -Raw -Encoding utf8
    if ($applyStatus -notmatch 'stage=failed:') {
        return $null
    }
    $failureJson = Join-Path $WorkDirectory 'failure.json'
    if (Test-Path -LiteralPath $failureJson -PathType Leaf) {
        try {
            $failDoc = Get-Content -LiteralPath $failureJson -Raw -Encoding utf8 | ConvertFrom-Json
            if (-not [string]::IsNullOrWhiteSpace([string]$failDoc.message)) {
                return [string]$failDoc.message
            }
        }
        catch {
            Write-Verbose "failure.json unreadable: $($_.Exception.Message)"
        }
    }
    return 'Apply failed (apply-status)'
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
    return $null
}

function Test-WinMintGuestEvidenceTerminal {
    <#
      Fail-closed S4 gate: Complete evidence alone is not terminal — live explorer shell
      and no Supervisor process mean FirstLogon handoff actually finished.
      ExplorerRunning: live probes pass $true/$false (explorer.exe process alive — a
      restored Shell value with a crashed explorer is not a desktop); static fixtures
      omit it ($null = neutral).
    #>
    param(
        [Parameter(Mandatory)] $EvidenceDoc,
        [Parameter(Mandatory)] [string] $LiveShell,
        [bool] $SupervisorRunning = $false,
        [string] $RequiredSmokeRunId = '',
        $ExplorerRunning = $null
    )
    if (-not [string]::IsNullOrWhiteSpace($RequiredSmokeRunId)) {
        $got = ''
        if ($EvidenceDoc.PSObject.Properties.Name -contains 'smokeRunId') {
            $got = [string]$EvidenceDoc.smokeRunId
        }
        if ($got -ne $RequiredSmokeRunId) { return $false }
    }
    $outcome = [string]$EvidenceDoc.outcome
    if ($outcome -eq 'Failed') { return $true }
    if ($outcome -ne 'Complete') { return $false }
    if ([string]$EvidenceDoc.statusCode -ne 'jobs.ok') { return $false }
    $phases = @($EvidenceDoc.phases)
    if ($phases -notcontains 'jobs.ok') { return $false }
    if ($phases -notcontains 'oobe.dismiss') { return $false }
    if (-not (Test-WinMintExplorerShellValue $LiveShell)) { return $false }
    if ($SupervisorRunning) { return $false }
    if ($ExplorerRunning -is [bool] -and -not $ExplorerRunning) { return $false }
    return $true
}
