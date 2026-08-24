#requires -Version 7.6
<#
.SYNOPSIS
  Hyper-V Smoke acceptance: Apply ISO → VM install → pull evidence → assert (S4).

.DESCRIPTION
  One entry for “run Smoke → evidence”. Not part of `just check` — use `just smoke`.

  Modes:
    Full run (default): publish Supervisor, Apply, create Gen2 VM, wait, pull, assert.
    -AssertOnly: validate an existing evidence folder (no Hyper-V).
    -SkipApply: reuse <Work>/out.iso from a prior Apply.

.NOTES
  Requires: Hyper-V, admin for Apply/VM, user-supplied Source ISO (ADR-001).
  Stall fail-fast: no guest progress for -StallMinutes ⇒ fail before wall clock
  (pre-heartbeat: CPU/reboot churn; after guest-up: Supervisor alive or new evidence).
  Reboot-loop fail-fast: more than -MaxSetupReboots setup reboots after the image applied.
  Empty-VHD fail-fast: dynamic VHD stays under 1GB for -EmptyVhdMinutes after Running (WinPE never applied).
  Elapsed time uses Stopwatch (QPC), not Get-Date — SL7's clock can jump.
  Script default wall is 90 minutes; `just smoke` passes 180 (winget/WSL on Default Switch NAT).
#>
param(
    [Parameter(ParameterSetName = 'Run')]
    [string] $Iso,

    [Parameter(ParameterSetName = 'Run')]
    [string] $Work = (Join-Path (Get-Location) '.scratch\smoke'),

    # ProfilePath (not $Profile — that shadows the pwsh automatic variable).
    [Parameter(ParameterSetName = 'Run')]
    [Alias('Profile')]
    [string] $ProfilePath = 'samples/sl7.profile.json',

    [Parameter(ParameterSetName = 'Run')]
    [string] $VmName = 'winmint-smoke',

    [Parameter(ParameterSetName = 'Run')]
    [int] $StallMinutes = 45,

    [Parameter(ParameterSetName = 'Run')]
    [int] $WallClockMinutes = 90,

    [Parameter(ParameterSetName = 'Run')]
    [int] $EmptyVhdMinutes = 8,

    # Setup reboots past this cap fail fast as REBOOT_LOOP (each also burns one guest autologon).
    [Parameter(ParameterSetName = 'Run')]
    [int] $MaxSetupReboots = 8,

    [Parameter(ParameterSetName = 'Run')]
    [switch] $Monitor,

    [Parameter(ParameterSetName = 'Run')]
    [switch] $SkipApply,

    # Attach to an in-progress winmint-smoke VM (setup reboot); do not recreate VHD.
    [Parameter(ParameterSetName = 'Run')]
    [switch] $ReuseVm,

    [Parameter(Mandatory, ParameterSetName = 'AssertOnly')]
    [switch] $AssertOnly,

    [Parameter(Mandatory, ParameterSetName = 'AssertOnly')]
    [string] $EvidenceDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\Resolve-OutputIso.ps1')

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $repoRoot
. (Join-Path $repoRoot 'tools\host\Invoke-ArtifactHygiene.ps1') -NoRun

. (Join-Path $repoRoot 'tools/vm/SmokeStatus.ps1')
. (Join-Path $repoRoot 'tools/host/Write-WinMintHostProgress.ps1')
. (Join-Path $repoRoot 'tools/AcceptanceManifest.ps1')

function Write-SmokeHostLine {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [string] $Activity = 'Smoke',
        [string] $Outcome = ''
    )
    $phase = @{ Lane = 'Smoke'; Name = $Name }
    if (-not [string]::IsNullOrWhiteSpace($Outcome)) { $phase.Outcome = $Outcome }
    Write-WinMintHostPhase @phase
    if ($Activity -eq 'wait') {
        Write-WinMintHostProgress -Activity wait -Status $Name
    }
    else {
        Write-WinMintHostProgress -Activity $Activity -Status $Name
    }
}
$statusPath = Join-Path $Work 'smoke-status.json'

$assertScript = Join-Path $PSScriptRoot 'Assert-SmokeEvidence.ps1'
$manifestPath = Join-Path $Work 'smoke-evidence\acceptance.manifest.json'
$runId = [guid]::NewGuid().ToString('N')
$outIso = $null
$runScratchHygiene = $false

if ($AssertOnly) {
    & $assertScript -EvidenceDir $EvidenceDir -StaticEvidenceOnly
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    exit 0
}

try {
if ([string]::IsNullOrWhiteSpace($Iso)) {
    throw 'Iso is required for a full Smoke run (user-supplied Source ISO).'
}
if (-not (Test-Path -LiteralPath $Iso)) {
    throw "Source ISO not found: $Iso"
}

# --- Preflight: fail fast before hours of DISM, not at the wait loop ---
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Smoke needs an elevated pwsh (Apply + Hyper-V).'
}
if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
    throw 'Hyper-V PowerShell module not available. Install Hyper-V or use -AssertOnly.'
}
if (-not (Get-VMSwitch -Name 'Default Switch' -ErrorAction SilentlyContinue)) {
    throw "Hyper-V 'Default Switch' not found — needed for guest network (winget prove-out)."
}
$natIp = Get-NetIPAddress -InterfaceAlias 'vEthernet (Default Switch)' -AddressFamily IPv4 -ErrorAction SilentlyContinue
if (-not $natIp) {
    throw "Default Switch has no IPv4 address (broken Hyper-V NAT parks OOBE at the network screen). Restart the Hyper-V host networking."
}
$workDrive = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Work))
$freeGB = [math]::Round((Get-PSDrive -Name $workDrive.Substring(0, 1)).Free / 1GB)
if ($freeGB -lt 40) {
    throw "Only ${freeGB}GB free on $workDrive — Smoke needs headroom for the 64GB dynamic VHD + Output ISO (40GB floor)."
}

# Local+autoLogon Profiles need explicit PS Direct credentials (workgroup guest).
# Resolve now — passwordPath included — so a missing secret fails here, not as a
# blocking New-PSSession credential prompt mid-wait (sl7.profile.json uses passwordPath).
$guestCred = Resolve-WinMintSmokeGuestCredential -ProfilePath $ProfilePath
$profileDoc = Get-Content -LiteralPath $ProfilePath -Raw -Encoding utf8 | ConvertFrom-Json

$evidenceOut = Join-Path $Work 'smoke-evidence'
$applyDir = Join-Path $evidenceOut 'apply'
$guestDir = Join-Path $evidenceOut 'guest'
# Fresh pull folder each run — do not treat prior guest JSON as success.
if (Test-Path -LiteralPath $guestDir) {
    Remove-Item -LiteralPath $guestDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $applyDir, $guestDir | Out-Null

$workFull = if ([IO.Path]::IsPathRooted($Work)) { $Work } else { Join-Path $repoRoot $Work }

# New run identity, stamped before the watcher spawns. Pass leftover/empty
# -PriorRunId: — the post-stamp file is this run, not prior.
Write-SmokeStatus -Path $statusPath -Phase (Resolve-SmokePhase -HostStage apply) `
    -VmName $VmName -StallMinutesLeft $StallMinutes -WallMinutesLeft $WallClockMinutes `
    -LastHostLine 'Smoke run starting' -OutputIso $null -RunId $runId

$pwshExe = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
$watcherMarker = Join-Path $workFull 'watch-smoke.pid'
$watcherAlive = $false
if (Test-Path -LiteralPath $watcherMarker -PathType Leaf) {
    $oldWatcher = 0
    if ([int]::TryParse((Get-Content -LiteralPath $watcherMarker -Raw).Trim(), [ref]$oldWatcher) -and $oldWatcher -gt 0) {
        $watcherAlive = $null -ne (Get-Process -Id $oldWatcher -ErrorAction SilentlyContinue)
    }
}
if ((Get-SmokeWatcherSpawnDecision -MarkerPidAlive:$watcherAlive) -eq 'spawn') {
    $watcher = Start-Process -FilePath $pwshExe -WorkingDirectory $repoRoot -PassThru -ArgumentList @(
        '-NoProfile',
        '-NonInteractive',
        '-File', (Join-Path $PSScriptRoot 'Watch-SmokeHost.ps1'),
        '-Work', $workFull,
        '-PriorRunId:'
    )
    Set-Content -LiteralPath $watcherMarker -Value $watcher.Id -Encoding utf8
}

$applyEvidence = Join-Path $Work 'evidence.json'
# Resolve pre-Apply only for -SkipApply reuse. A full run resolves after Apply —
# stale winmint_*.iso from failed prior runs must not fail-close a fresh Apply.
$outIso = if ($SkipApply) { Resolve-WinMintOutputIso -WorkDirectory $Work } else { $null }
if ($SkipApply) { $runScratchHygiene = $true }
if (-not $SkipApply) {
    Write-SmokeHostLine -Name 'Publishing Supervisor (Release AOT)…' -Activity publish
    & just publish-provisioning
    if ($LASTEXITCODE -ne 0) { throw "just publish-provisioning failed: $LASTEXITCODE" }

    # Clear prior-run Apply projections so a crashed Apply cannot resurrect an old
    # stage=failed, lane marker, keep-flag pins, or expected digests into this run.
    $priorProjections = @('apply-status.txt', 'failure.json', 'evidence.json', 'stages.json', 'expected-evidence.json') |
        ForEach-Object { Join-Path $Work $_ }
    Remove-Item -LiteralPath $priorProjections -Force -ErrorAction SilentlyContinue

    Write-SmokeStatus -Path $statusPath -Phase (Resolve-SmokePhase -HostStage apply) `
        -VmName $VmName -StallMinutesLeft $StallMinutes -WallMinutesLeft $WallClockMinutes `
        -LastHostLine "Applying Profile=$ProfilePath" -OutputIso $null -RunId $runId
    Write-SmokeHostLine -Name "Applying Profile=$ProfilePath Iso=$Iso Work=$Work (Test lane, smoke stubs on)…" -Activity apply
    $runScratchHygiene = $true
    try {
        & just apply-maintainer $Iso $Work $ProfilePath true
        $applyFail = Get-WinMintApplyHostFailure -WorkDirectory $workFull
        if ($applyFail) { throw $applyFail }
        if ($LASTEXITCODE -ne 0) { throw "Apply failed: $LASTEXITCODE" }
    }
    catch {
        throw
    }

    # Re-resolve after Apply (dynamic leaf).
    $outIso = Resolve-WinMintOutputIso -WorkDirectory $Work
}

if ([string]::IsNullOrWhiteSpace($outIso) -or -not (Test-Path -LiteralPath $outIso)) {
    throw "Output ISO missing under $Work (run Apply or omit -SkipApply)"
}

# Lane marker from Apply evidence (fail closed — do not invent).
if (-not (Test-Path -LiteralPath $applyEvidence)) {
    throw "Apply evidence.json missing under $Work (lane marker required for S4)"
}
Copy-Item -LiteralPath $applyEvidence -Destination (Join-Path $applyDir 'evidence.json') -Force
$applyExpected = Join-Path $Work 'expected-evidence.json'
if (Test-Path -LiteralPath $applyExpected -PathType Leaf) {
    Copy-Item -LiteralPath $applyExpected -Destination (Join-Path $applyDir 'expected-evidence.json') -Force
}

# --- Hyper-V ---
Enable-VMEventing -Force -ErrorAction SilentlyContinue

$vhdx = Join-Path $Work 'smoke.vhdx'
$existing = Get-VM -Name $VmName -ErrorAction SilentlyContinue
if ($ReuseVm) {
    if (-not $existing) { throw "ReuseVm: VM '$VmName' not found" }
    Write-SmokeHostLine -Name "Reusing existing VM $VmName (state=$($existing.State))…" -Activity vm
    Disable-VMIntegrationService -VMName $VmName -Name 'Time Synchronization' -ErrorAction SilentlyContinue
    if ($existing.State -eq 'Off') {
        Start-VM -Name $VmName
    }
}
else {
    Write-SmokeHostLine -Name "Preparing VM $VmName…" -Activity vm
    # Soft-guard: do not Remove-VM / rewrite out.iso while another Smoke wait loop is live.
    if ($existing) {
        Stop-VM -Name $VmName -TurnOff -Force -ErrorAction SilentlyContinue
        Get-VMSnapshot -VMName $VmName -ErrorAction SilentlyContinue | Remove-VMSnapshot -ErrorAction SilentlyContinue
        Remove-VM -Name $VmName -Force
    }
    # Dynamic VHD may be renamed by Hyper-V; clear any smoke*.vhdx under Work.
    Get-ChildItem -LiteralPath $Work -Filter 'smoke*.vhdx' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $Work -Filter 'smoke_*.avhdx' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $vhdx) { Remove-Item -LiteralPath $vhdx -Force }

    # Gen2, Secure Boot off + no vTPM (Start-VM times out with vTPM on this host — SPLASH).
    # WinPE apply stamps LabConfig on the applied-image SYSTEM hive.
    New-VHD -Path $vhdx -SizeBytes 64GB -Dynamic | Out-Null
    New-VM -Name $VmName -Generation 2 -VHDPath $vhdx | Out-Null
    # 8GB is apply/OOBE headroom; 4GB is only the Win11 floor. Not a #118 acceptance bar.
    Set-VMMemory -VMName $VmName -DynamicMemoryEnabled $false -StartupBytes (Get-SmokeVmStartupBytes)
    Set-VM -Name $VmName -AutomaticCheckpointsEnabled $false
    Set-VMFirmware -VMName $VmName -EnableSecureBoot Off
    Set-VMProcessor -VMName $VmName -Count 4
    # Guest NAT for winget/source (prior Smoke was offline-friendly stubs; Default Switch = Hyper-V NAT).
    $switch = Get-VMSwitch -Name 'Default Switch' -ErrorAction SilentlyContinue
    if (-not $switch) {
        throw "Hyper-V 'Default Switch' not found — needed for guest network (winget prove-out)."
    }
    Connect-VMNetworkAdapter -VMName $VmName -Name 'Network Adapter' -SwitchName 'Default Switch'
    # DVD boot from applied ISO
    $dvd = Get-VMDvdDrive -VMName $VmName -ErrorAction SilentlyContinue
    if (-not $dvd) {
        Add-VMDvdDrive -VMName $VmName -Path $outIso
    }
    else {
        Set-VMDvdDrive -VMName $VmName -Path $outIso
    }
    # Boot from DVD first (empty VHD otherwise triggers "Press any key to boot from CD…").
    $hddDev = Get-VMHardDiskDrive -VMName $VmName | Select-Object -First 1
    $dvdDev = Get-VMDvdDrive -VMName $VmName
    Set-VMFirmware -VMName $VmName -BootOrder $dvdDev, $hddDev

    # Disable guest IC time sync — host/guest NTP jumps otherwise blow wall-facing clocks
    # during settle (product deadlines are monotonic; harness still removes the class of jump).
    Disable-VMIntegrationService -VMName $VmName -Name 'Time Synchronization'

    # Hyper-V media ACL (SPLASH spike)
    $aclRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'NT VIRTUAL MACHINE\Virtual Machines', 'Read', 'Allow')
    foreach ($media in @($outIso, $vhdx)) {
        if (-not (Test-Path -LiteralPath $media)) { continue }
        $acl = Get-Acl -LiteralPath $media
        $acl.AddAccessRule($aclRule)
        Set-Acl -LiteralPath $media -AclObject $acl
    }

    Start-VM -Name $VmName
}

Write-SmokeHostLine -Name "VM ready. Waiting for guest evidence (stall=${StallMinutes}m, empty-vhd=${EmptyVhdMinutes}m, wall=${WallClockMinutes}m)…" -Activity wait
if ($Monitor) { Start-SmokeMonitor -VmName $VmName }

$wallSw = [Diagnostics.Stopwatch]::StartNew()
$stallSw = [Diagnostics.Stopwatch]::StartNew()
$nudgeSw = [Diagnostics.Stopwatch]::StartNew()
$script:emptyVhdSw = $null

$expectNativePackageAudit = $false
if ($null -ne $profileDoc -and $profileDoc.PSObject.Properties.Name -contains 'packages') {
    $packages = $profileDoc.packages
    if ($null -ne $packages -and $packages.PSObject.Properties.Name -contains 'winget') {
        $wingetIds = @($packages.winget | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        $expectNativePackageAudit = $wingetIds.Count -gt 0
    }
}

# Keep-flag pins from Apply Materialize (stages.json) — not Profile debloat.* (CONTRACTS ownership).
$stagesPath = Join-Path $Work 'stages.json'
if (-not (Test-Path -LiteralPath $stagesPath)) {
    throw "stages.json missing under $Work (Apply materialize required for keep-flag pins)"
}
try {
    $stagesDoc = Get-Content -LiteralPath $stagesPath -Raw -Encoding utf8 | ConvertFrom-Json
}
catch {
    throw "stages.json unreadable under $Work : $($_.Exception.Message)"
}

function Get-PayloadJsonIds {
    param(
        [Parameter(Mandatory)] $StagesDoc,
        [Parameter(Mandatory)] [string] $Opcode,
        [Parameter(Mandatory)] [string] $PathParam
    )
    $stage = @($StagesDoc.stages) |
        Where-Object { [string]$_.opcode -eq $Opcode } |
        Select-Object -First 1
    if ($null -eq $stage) { return @() }
    $path = [string]$stage.parameters.$PathParam
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    return @(Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json)
}

$pinnedRemoveAppx = @(Get-PayloadJsonIds -StagesDoc $stagesDoc -Opcode 'RemoveProvisionedAppx' -PathParam 'packageFamilyNamesPath')
$pinnedOnlineRemoveAppx = @()
if ($pinnedRemoveAppx.Count -eq 0 -and $null -ne $profileDoc -and $profileDoc.PSObject.Properties.Name -contains 'debloat') {
    $debloat = $profileDoc.debloat
    if ($null -ne $debloat -and $debloat.PSObject.Properties.Name -contains 'removeProvisionedAppx') {
        $mode = if ($debloat.PSObject.Properties.Name -contains 'mode') { [string]$debloat.mode } else { '' }
        if ([string]::IsNullOrWhiteSpace($mode) -or $mode -eq 'online') {
            $pinnedOnlineRemoveAppx = @($debloat.removeProvisionedAppx | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        }
    }
}
$pinnedRemoveCapabilities = @(Get-PayloadJsonIds -StagesDoc $stagesDoc -Opcode 'RemoveCapabilities' -PathParam 'namesPath')
$pinnedDisableOptionalFeatures = @(Get-PayloadJsonIds -StagesDoc $stagesDoc -Opcode 'DisableOptionalFeatures' -PathParam 'namesPath')

function Test-GuestEvidenceReady {
    # Reboot evidence is not terminal — keep waiting for resume → Complete (ticket 17).
    # Complete evidence alone is not terminal — require live explorer shell and no Supervisor process.
    try {
        $sessionParams = @{ VMName = $VmName; ErrorAction = 'Stop' }
        if ($null -ne $guestCred) { $sessionParams['Credential'] = $guestCred }
        $session = New-PSSession @sessionParams
        try {
            # Disk is booting Windows — HDD first; eject DVD only after heartbeat (not mid-WinPE reboot).
            Prefer-DiskBoot
            Dismount-InstallDvdWhenWindowsBoots

            $remotePaths = @(Invoke-Command -Session $session -ScriptBlock {
                $dir = Join-Path $env:ProgramData 'WinMint\evidence'
                if (-not (Test-Path -LiteralPath $dir)) { return @() }
                Get-ChildItem -LiteralPath $dir -Filter 'evidence-*.json' -File |
                    ForEach-Object { $_.FullName }
            })
            foreach ($remote in $remotePaths) {
                if ([string]::IsNullOrWhiteSpace([string]$remote)) { continue }
                $leaf = Split-Path $remote -Leaf
                Copy-Item -FromSession $session -Path $remote -Destination (Join-Path $guestDir $leaf) -Force
            }
            $selected = Select-WinMintGuestEvidencePath -Directory $guestDir -RequiredSmokeRunId $runId
            if (-not $selected) { return $false }

            $pulled = Get-Content -LiteralPath $selected -Raw -Encoding utf8 | ConvertFrom-Json
            $outcome = [string]$pulled.outcome
            if ($outcome -eq 'Reboot') {
                Write-SmokeHostLine -Name 'Guest evidence outcome=Reboot — waiting for checkpoint resume…' -Activity wait
                return $false
            }

            $live = Invoke-Command -Session $session -ScriptBlock {
                $shell = $null
                try {
                    $shell = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name Shell -ErrorAction Stop).Shell
                }
                catch { $null = $_ }
                $supervisor = $false
                try {
                    $supervisor = @(Get-Process -Name 'Supervisor' -ErrorAction SilentlyContinue).Count -gt 0
                }
                catch { $null = $_ }
                $explorer = $false
                try {
                    $explorer = @(Get-Process -Name 'explorer' -ErrorAction SilentlyContinue).Count -gt 0
                }
                catch { $null = $_ }
                [pscustomobject]@{
                    Shell              = [string]$shell
                    SupervisorRunning  = [bool]$supervisor
                    ExplorerRunning    = [bool]$explorer
                }
            }
            $script:LastProbeError = ''
            $script:LastSupervisorRunning = [bool]$live.SupervisorRunning
            $evRows = @(Get-WinMintGuestEvidenceRows -Directory $guestDir -RequiredSmokeRunId $runId)
            $newest = @($evRows | Sort-Object SortKey -Descending | Select-Object -First 1)
            if ($newest.Count -ge 1) {
                $script:GuestEvidenceFingerprint = "$($newest[0].SortKey):$($newest[0].Outcome)"
            }

            if ($expectNativePackageAudit) {
                $nativeRemote = Invoke-Command -Session $session -ScriptBlock {
                    $p = Join-Path $env:ProgramData 'WinMint\evidence\native-packages.json'
                    if (Test-Path -LiteralPath $p) { $p } else { $null }
                }
                if ($nativeRemote) {
                    Copy-Item -FromSession $session -Path $nativeRemote -Destination (Join-Path $guestDir 'native-packages.json') -Force
                }
            }

            $chromeRemote = Invoke-Command -Session $session -ScriptBlock {
                $p = Join-Path $env:ProgramData 'WinMint\shell-chrome.json'
                if (Test-Path -LiteralPath $p) { $p } else { $null }
            }
            if ($chromeRemote) {
                Copy-Item -FromSession $session -Path $chromeRemote -Destination (Join-Path $guestDir 'shell-chrome.json') -Force
            }

            if (-not (Test-WinMintGuestEvidenceTerminal -EvidenceDoc $pulled `
                    -LiveShell ([string]$live.Shell) -SupervisorRunning:$live.SupervisorRunning `
                    -RequiredSmokeRunId $runId -ExplorerRunning $live.ExplorerRunning)) {
                if ($outcome -eq 'Complete') {
                    Write-SmokeHostLine -Name ("Guest evidence Complete but handoff not verified " +
                        "(shell='$($live.Shell)' supervisor=$($live.SupervisorRunning) explorer=$($live.ExplorerRunning)) — waiting…") -Activity wait
                }
                return $false
            }

            if ($live.Shell) {
                Set-Content -LiteralPath (Join-Path $guestDir 'winlogon-shell.txt') -Value ([string]$live.Shell).Trim() -Encoding utf8
            }
            return $true
        }
        finally {
            Remove-PSSession $session -ErrorAction SilentlyContinue
        }
    }
    catch {
        # PS Direct unavailable until guest is up / integration services ready
        $script:LastProbeError = [string]$_.Exception.Message
        $script:LastSupervisorRunning = $false
    }
    return $false
}

$script:DiskBootPreferred = $false
$script:DvdEjected = $false
$script:SmokeRunIdStamped = $false
$script:GuestUpSticky = $false
$script:ConsecutiveHeartbeatOk = 0
$script:LastProbeError = ''
$script:LastSupervisorRunning = $false
$script:GuestEvidenceFingerprint = ''
$script:LastGuestEvidenceFingerprint = ''
$script:LastVmState = ''
$script:SetupRebootCount = 0
$script:HalfStallShot = $false
function Test-SmokeVhdHasImage {
    try {
        $drive = Get-VMHardDiskDrive -VMName $VmName | Select-Object -First 1
        if (-not $drive -or [string]::IsNullOrWhiteSpace($drive.Path)) { return $false }
        # Dynamic VHD FileSize stays tiny until WinPE actually applies the WIM.
        return ((Get-VHD -Path $drive.Path).FileSize -ge 1GB)
    }
    catch {
        return $false
    }
}

function Test-GuestWindowsHeartbeat {
    try {
        $hb = Get-VMIntegrationService -VMName $VmName |
            Where-Object { $_.Name -eq 'Heartbeat' } |
            Select-Object -First 1
        return [int]$hb.PrimaryOperationalStatus -eq 2
    }
    catch {
        return $false
    }
}

function Prefer-DiskBoot {
    $decision = Get-SmokePreferDiskBootDecision `
        -AlreadyPreferred $script:DiskBootPreferred `
        -VhdHasImage (Test-SmokeVhdHasImage)
    if ($decision -eq 'skip') { return }
    if ($decision -eq 'keep-dvd') {
        Write-SmokeHostLine -Name 'Setup reboot before disk has an image — keeping install DVD attached.' -Activity wait
        return
    }
    try {
        $hddDev = Get-VMHardDiskDrive -VMName $VmName | Select-Object -First 1
        $dvdDev = Get-VMDvdDrive -VMName $VmName
        if ($null -eq $hddDev) { return }
        if ($null -ne $dvdDev) {
            Set-VMFirmware -VMName $VmName -BootOrder $hddDev, $dvdDev
        }
        else {
            Set-VMFirmware -VMName $VmName -BootOrder $hddDev
        }
        $script:DiskBootPreferred = $true
        Write-SmokeHostLine -Name 'Preferred HDD boot (install DVD attached until Windows heartbeat).' -Activity wait
    }
    catch {
        Write-Warning "Could not prefer disk boot: $($_.Exception.Message)"
    }
}

function Dismount-InstallDvdWhenWindowsBoots {
    $decision = Get-SmokeEjectDvdDecision `
        -AlreadyEjected $script:DvdEjected `
        -DiskBootPreferred $script:DiskBootPreferred `
        -HeartbeatOk:(Test-GuestWindowsHeartbeat)
    if ($decision -eq 'skip') { return }
    try {
        $dvdDev = Get-VMDvdDrive -VMName $VmName
        if ($null -ne $dvdDev -and -not [string]::IsNullOrWhiteSpace([string]$dvdDev.Path)) {
            Set-VMDvdDrive -VMName $VmName -Path $null
            Write-SmokeHostLine -Name 'Ejected install DVD after Windows heartbeat.' -Activity wait
        }
        $script:DvdEjected = $true
    }
    catch {
        Write-Warning "Could not eject install DVD: $($_.Exception.Message)"
    }
}

function Send-VmBootNudge {
    # Gen2 + empty VHD often sits on "Press any key to boot from CD or DVD…"
    try {
        $vmCs = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='$VmName'" -ErrorAction Stop
        $kb = Get-CimAssociatedInstance -InputObject $vmCs -ResultClassName Msvm_Keyboard -ErrorAction Stop | Select-Object -First 1
        if ($null -eq $kb) { return }
        foreach ($code in @(0x20, 0x0D)) {
            # 0x20 = VK_SPACE, 0x0D = VK_RETURN
            Invoke-CimMethod -InputObject $kb -MethodName PressKey -Arguments @{ keyCode = $code } | Out-Null
            Start-Sleep -Milliseconds 100
            Invoke-CimMethod -InputObject $kb -MethodName ReleaseKey -Arguments @{ keyCode = $code } | Out-Null
            Start-Sleep -Milliseconds 100
        }
        Write-SmokeHostLine -Name 'Sent Space/Enter to VM (DVD boot keypress).' -Activity wait
    }
    catch {
        Write-Warning "Could not send boot keypress to VM: $($_.Exception.Message)"
    }
}

Send-VmBootNudge

function Try-StampSmokeRunId {
    if ($script:SmokeRunIdStamped) { return }
    try {
        $sessionParams = @{ VMName = $VmName; ErrorAction = 'Stop' }
        if ($null -ne $guestCred) { $sessionParams['Credential'] = $guestCred }
        $stampSession = New-PSSession @sessionParams
        try {
            Invoke-Command -Session $stampSession -ScriptBlock {
                $root = Join-Path $env:ProgramData 'WinMint'
                New-Item -ItemType Directory -Force -Path $root | Out-Null
                Set-Content -LiteralPath (Join-Path $root 'smoke-run.id') -Value ($using:runId).Trim() -Encoding utf8 -NoNewline
            }
            $script:SmokeRunIdStamped = $true
            Write-SmokeHostLine -Name "Stamped guest smoke-run.id=$runId" -Activity wait
        }
        finally {
            Remove-PSSession $stampSession -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Warning "Could not stamp guest smoke-run.id yet: $($_.Exception.Message)"
    }
}

$wallLeft = [math]::Max(0, [int]($WallClockMinutes - $wallSw.Elapsed.TotalMinutes))
# Outer try (line ~82) owns the catch: Apply failures and wait/assert failures share
# one smoke-status + acceptance-manifest failure path.
while ($wallSw.Elapsed.TotalMinutes -lt $WallClockMinutes) {
        if (Test-GuestEvidenceReady) {
            Write-SmokeHostLine -Name 'Guest evidence pulled.' -Activity wait
            break
        }

        $vm = Get-VM -Name $VmName
        $vmStateNow = [string]$vm.State
        # Setup reboots flip Running → Stopping → Off → Starting → Running; do not fail-closed.
        # Eject DVD only after the VHD has an applied image so a WinPE reboot cannot leave an empty disk.
        switch ($vmStateNow) {
            'Running' {
                # HDD first before wpeutil reboot. Waiting for Stopping misses the flip and
                # WinPE LaunchApply runs again (clean + apply) if DVD is still attached.
                Prefer-DiskBoot
                Dismount-InstallDvdWhenWindowsBoots
            }
            'Starting' { Write-SmokeHostLine -Name 'VM Starting (setup reboot)…' -Activity wait }
            'Stopping' {
                Write-SmokeHostLine -Name 'VM Stopping (setup reboot)…' -Activity wait
                Prefer-DiskBoot
            }
            'Off' {
                Write-SmokeHostLine -Name 'VM Off during setup — starting again…' -Activity wait
                Prefer-DiskBoot
                Start-VM -Name $VmName -ErrorAction SilentlyContinue
            }
            default {
                throw "VM in unexpected state: $($vm.State)"
            }
        }

        $cpu = 0
        try { $cpu = [int]$vm.CPUUsage } catch { $cpu = 0 }
        $vhdHasImage = $false
        try {
            $drive = Get-VMHardDiskDrive -VMName $VmName | Select-Object -First 1
            if ($drive) { $vhdHasImage = ((Get-VHD -Path $drive.Path).FileSize -ge 1GB) }
        } catch { $vhdHasImage = $false }
        if ((Get-SmokeSetupRebootTransition -LastVmState $script:LastVmState -VmState $vmStateNow -VhdHasImage:$vhdHasImage) -eq 'count') {
            $script:SetupRebootCount++
        }
        if ((Get-SmokeNudgeRearmDecision -LastVmState $script:LastVmState -VmState $vmStateNow -DiskBootPreferred:$script:DiskBootPreferred) -eq 'rearm') {
            $nudgeSw.Restart()
            Write-SmokeHostLine -Name 'Re-armed DVD boot nudge after Off→Running (DVD still first).' -Activity wait
        }
        $script:LastVmState = $vmStateNow
        $guestProgress = (Get-SmokeGuestProgressDecision `
            -LastFingerprint $script:LastGuestEvidenceFingerprint `
            -Fingerprint $script:GuestEvidenceFingerprint `
            -SupervisorRunning:$script:LastSupervisorRunning) -eq 'progress'
        if ($guestProgress) { $script:LastGuestEvidenceFingerprint = $script:GuestEvidenceFingerprint }
        if ((Get-SmokeStallExtendDecision -VmState $vmStateNow -Cpu $cpu `
                -GuestUpSticky:$script:GuestUpSticky -GuestProgress:$guestProgress) -eq 'extend') {
            $stallSw.Restart()
        }

        $vhdBytes = 0
        try {
            $drive = Get-VMHardDiskDrive -VMName $VmName | Select-Object -First 1
            if ($drive) { $vhdBytes = [long](Get-VHD -Path $drive.Path).FileSize }
        } catch { $vhdBytes = 0 }

        if ([string]$vm.State -eq 'Running' -and $vhdBytes -lt 1GB) {
            if ($null -eq $script:emptyVhdSw) {
                $script:emptyVhdSw = [Diagnostics.Stopwatch]::StartNew()
            }
            elseif (-not $script:emptyVhdSw.IsRunning) {
                $script:emptyVhdSw.Start()
            }
        }
        else {
            if ($null -ne $script:emptyVhdSw -and $script:emptyVhdSw.IsRunning) {
                $script:emptyVhdSw.Stop()
            }
            if ($vhdBytes -ge 1GB) {
                $script:emptyVhdSw = $null
            }
        }

        $hb = Test-GuestWindowsHeartbeat
        if ((Get-SmokeRunIdStampDecision -AlreadyStamped:$script:SmokeRunIdStamped -HeartbeatOk:$hb) -eq 'try-stamp') {
            Try-StampSmokeRunId
        }
        $phaseRes = Get-SmokeWaitPhaseSticky -VmState ([string]$vm.State) -VhdFileSizeBytes $vhdBytes `
            -HeartbeatOk:$hb -GuestUpSticky:$script:GuestUpSticky `
            -ConsecutiveHeartbeatOk $script:ConsecutiveHeartbeatOk
        $phase = [string]$phaseRes.Phase
        $script:GuestUpSticky = [bool]$phaseRes.GuestUpSticky
        $script:ConsecutiveHeartbeatOk = [int]$phaseRes.ConsecutiveHeartbeatOk
        $stallLeft = [math]::Max(0, [int]($StallMinutes - $stallSw.Elapsed.TotalMinutes))
        $wallLeft = [math]::Max(0, [int]($WallClockMinutes - $wallSw.Elapsed.TotalMinutes))
        $hostLine = "VM $vmStateNow"
        if ($script:LastProbeError) { $hostLine = "PS Direct: $($script:LastProbeError)" }
        Write-SmokeStatus -Path $statusPath -Phase $phase -VmName $VmName -VmState $vmStateNow `
            -Cpu $cpu -Heartbeat $(if ($hb) { 'OK' } else { 'No Contact' }) `
            -VhdFileSizeMB ([int][math]::Round($vhdBytes / 1MB)) `
            -StallMinutesLeft $stallLeft -WallMinutesLeft $wallLeft `
            -LastHostLine $hostLine -OutputIso $outIso -RunId $runId `
            -SetupRebootCount $script:SetupRebootCount

        $emptySecs = 0
        if ($null -ne $script:emptyVhdSw) {
            $emptySecs = [int]$script:emptyVhdSw.Elapsed.TotalSeconds
        }
        $verdict = Get-SmokeWatchVerdict -Phase $phase -VmState ([string]$vm.State) `
            -VhdFileSizeMB ([int][math]::Round($vhdBytes / 1MB)) `
            -EmptyVhdRunningSeconds $emptySecs `
            -EmptyVhdFailAfterSeconds ([int]($EmptyVhdMinutes * 60))
        if ($verdict -eq 'empty-vhd') {
            throw "EMPTY_VHD: WinPE has not applied (VHD FileSize still under 1GB) for ${EmptyVhdMinutes} minutes after Running."
        }
        if ((Get-SmokeRebootLoopVerdict -SetupRebootCount $script:SetupRebootCount -MaxSetupReboots $MaxSetupReboots) -eq 'reboot-loop') {
            throw "REBOOT_LOOP: $($script:SetupRebootCount) setup reboots after the image applied (cap $MaxSetupReboots)."
        }

        if (-not $script:HalfStallShot -and $stallSw.Elapsed.TotalMinutes -ge ($StallMinutes / 2.0)) {
            Save-SmokeVmScreenshot -VmName $VmName -Path (Join-Path $evidenceOut 'console-half-stall.bmp') | Out-Null
            $script:HalfStallShot = $true
        }

        if ($stallSw.Elapsed.TotalMinutes -ge $StallMinutes) {
            throw "STALL_SUSPECT: no guest progress for ${StallMinutes} minutes (fail-fast before WallClockTimeout)."
        }

        # Boot nudge only while DVD is still first (before Prefer-DiskBoot).
        if (-not $script:DiskBootPreferred -and $nudgeSw.Elapsed.TotalMinutes -lt 3 -and $vmStateNow -eq 'Running') {
            Send-VmBootNudge
        }

        Start-Sleep -Seconds 30
    }

    if (-not (Get-ChildItem -LiteralPath $guestDir -Filter 'evidence-*.json' -ErrorAction SilentlyContinue)) {
        throw "Wall clock elapsed without guest evidence under $guestDir"
    }

    Write-SmokeStatus -Path $statusPath -Phase (Resolve-SmokePhase -HostStage assert) `
        -VmName $VmName -StallMinutesLeft 0 -WallMinutesLeft $wallLeft `
        -LastHostLine 'Guest evidence pulled.' -OutputIso $outIso -RunId $runId
    $shellForAssert = ([string](Get-Content -LiteralPath (Join-Path $guestDir 'winlogon-shell.txt') -Raw -Encoding utf8)).Trim()
    & $assertScript -EvidenceDir $evidenceOut `
        -LiveShell $shellForAssert `
        -SupervisorRunning:$false `
        -RequiredSmokeRunId $runId `
        -PinnedRemoveAppx $pinnedRemoveAppx `
        -PinnedOnlineRemoveAppx $pinnedOnlineRemoveAppx `
        -PinnedRemoveCapabilities $pinnedRemoveCapabilities `
        -PinnedDisableOptionalFeatures $pinnedDisableOptionalFeatures `
        $(if ($expectNativePackageAudit) { '-ExpectNativePackageAudit' })
    if ($LASTEXITCODE -ne 0) { throw "Assert-SmokeEvidence exit $LASTEXITCODE" }
    if (-not $SkipApply) {
        $applyDoc = Get-Content -LiteralPath $applyEvidence -Raw -Encoding utf8 | ConvertFrom-Json
        $digestMap = @{}
        foreach ($p in @($applyDoc.digests.PSObject.Properties)) { $digestMap[[string]$p.Name] = [string]$p.Value }
        $sourceSha = if ($digestMap.ContainsKey('source.isoSha256')) { $digestMap['source.isoSha256'] } else { $null }
        $sourceLength = if ($digestMap.ContainsKey('source.isoLength')) { [long]$digestMap['source.isoLength'] } else { 0 }
        $outputSha = if ($digestMap.ContainsKey('outputIso.sha256')) { $digestMap['outputIso.sha256'] } else { $null }
        $packageStrict = $null
        if ($applyDoc.PSObject.Properties.Name -contains 'packageStrict') { $packageStrict = [bool]$applyDoc.packageStrict }
        $artifactRoot = (Resolve-Path $Work).Path
        $outputRelative = [IO.Path]::GetRelativePath($artifactRoot, (Resolve-Path $outIso).Path).Replace('\', '/')
        Write-WinMintAcceptanceManifest -Path $manifestPath -AcceptanceKind Smoke -Outcome green `
            -Lane ([string]$applyDoc.lane) -RepositoryRoot $repoRoot -ProfilePath $ProfilePath `
            -SourceIsoPath $Iso -OutputIsoPath $outIso -SourceIsoSha256 $sourceSha `
            -SourceIsoLength $sourceLength -OutputIsoSha256 $outputSha `
            -SourceEvidenceSchemas @(
                'winmint.image.evidence/v1',
                'winmint.provisioning.evidence/v1',
                'winmint.smoke.acceptance/v1'
            ) -ArtifactPaths @($outputRelative, 'smoke-evidence/apply/evidence.json', 'smoke-evidence/guest') `
            -PackageStrict ([Nullable[bool]]$packageStrict)
    }
    Write-SmokeStatus -Path $statusPath -Phase (Resolve-SmokePhase -HostStage green) `
        -VmName $VmName -LastHostLine 'Smoke green' -OutputIso $outIso -RunId $runId
    Write-SmokeHostLine -Name "Smoke green. Evidence: $evidenceOut" -Outcome ok
    Write-WinMintHostProgress -Activity Smoke -Completed
}
catch {
    $failMsg = [string]$_.Exception.Message
    Write-SmokeStatus -Path $statusPath -Phase (Resolve-SmokePhase -HostStage failed) `
        -VmName $VmName -LastHostLine $failMsg -OutputIso $outIso -RunId $runId
    try {
        if (Get-Command Get-VM -ErrorAction SilentlyContinue) {
            $failVm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
            if ($failVm) {
                Save-SmokeVmScreenshot -VmName $VmName -Path (Join-Path $Work 'smoke-evidence\console-failed.bmp') | Out-Null
                if ((Get-SmokeSuspendVmDecision -FailureMessage $failMsg) -eq 'suspend') {
                    Suspend-VM -Name $VmName -ErrorAction SilentlyContinue
                    Write-SmokeHostLine -Name "Suspended $VmName for post-mortem (VMConnect still works)." -Outcome failed
                }
            }
        }
    }
    catch {
        Write-Warning "Could not capture/suspend VM after failure: $($_.Exception.Message)"
    }
    Write-WinMintHostProgress -Activity Smoke -Completed
    try {
        Write-WinMintAcceptanceManifest -Path $manifestPath -AcceptanceKind Smoke -Outcome failed `
            -Lane Test -RepositoryRoot $repoRoot -SourceEvidenceSchemas @('winmint.smoke.acceptance/v1') `
            -ArtifactPaths @('smoke-status.json')
    }
    catch {
        Write-Warning "Could not write failure acceptance manifest: $($_.Exception.Message)"
    }
    throw
}
finally {
    if ($runScratchHygiene) { Invoke-WinMintScratchHygiene -RepoRoot $repoRoot }
}
