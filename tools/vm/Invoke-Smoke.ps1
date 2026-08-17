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
  Stall fail-fast: no guest evidence progress for -StallMinutes ⇒ fail before 90 min wall clock.
#>
param(
    [Parameter(ParameterSetName = 'Run')]
    [string] $Iso,

    [Parameter(ParameterSetName = 'Run')]
    [string] $Work = (Join-Path (Get-Location) '.scratch\smoke'),

    [Parameter(ParameterSetName = 'Run')]
    [string] $Profile = 'samples/acceptance.profile.json',

    [Parameter(ParameterSetName = 'Run')]
    [string] $VmName = 'winmint-smoke',

    [Parameter(ParameterSetName = 'Run')]
    [int] $StallMinutes = 45,

    [Parameter(ParameterSetName = 'Run')]
    [int] $WallClockMinutes = 90,

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

. (Join-Path $repoRoot 'tools/vm/SmokeStatus.ps1')
$statusPath = Join-Path $Work 'smoke-status.json'

$assertScript = Join-Path $PSScriptRoot 'Assert-SmokeEvidence.ps1'

if ($AssertOnly) {
    & $assertScript -EvidenceDir $EvidenceDir
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Iso)) {
    throw 'Iso is required for a full Smoke run (user-supplied Source ISO).'
}
if (-not (Test-Path -LiteralPath $Iso)) {
    throw "Source ISO not found: $Iso"
}

$evidenceOut = Join-Path $Work 'smoke-evidence'
$applyDir = Join-Path $evidenceOut 'apply'
$guestDir = Join-Path $evidenceOut 'guest'
# Fresh pull folder each run — do not treat prior guest JSON as success.
if (Test-Path -LiteralPath $guestDir) {
    Remove-Item -LiteralPath $guestDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $applyDir, $guestDir | Out-Null

$applyEvidence = Join-Path $Work 'evidence.json'
$outIso = Resolve-WinMintOutputIso -WorkDirectory $Work
if (-not $SkipApply) {
    Write-Host 'Publishing Supervisor (Release AOT)…'
    & just publish-provisioning
    if ($LASTEXITCODE -ne 0) { throw "just publish-provisioning failed: $LASTEXITCODE" }

    Write-SmokeStatus -Path $statusPath -Phase (Resolve-SmokePhase -HostStage apply) `
        -VmName $VmName -StallMinutesLeft $StallMinutes -WallMinutesLeft $WallClockMinutes `
        -LastHostLine "Applying Profile=$Profile" -OutputIso $null
    Write-Host "Applying Profile=$Profile Iso=$Iso Work=$Work (Test lane, smoke stubs on)…"
    & just apply-maintainer $Iso $Work $Profile true
    if ($LASTEXITCODE -ne 0) { throw "Apply failed: $LASTEXITCODE" }

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
if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
    throw 'Hyper-V PowerShell module not available. Install Hyper-V or use -AssertOnly.'
}

$vhdx = Join-Path $Work 'smoke.vhdx'
$existing = Get-VM -Name $VmName -ErrorAction SilentlyContinue
if ($ReuseVm) {
    if (-not $existing) { throw "ReuseVm: VM '$VmName' not found" }
    Write-Host "Reusing existing VM $VmName (state=$($existing.State))…"
    Disable-VMIntegrationService -VMName $VmName -Name 'Time Synchronization' -ErrorAction SilentlyContinue
    if ($existing.State -eq 'Off') {
        Start-VM -Name $VmName
    }
}
else {
    Write-Host "Preparing VM $VmName…"
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
    Set-VMMemory -VMName $VmName -DynamicMemoryEnabled $false -StartupBytes 8GB
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

Write-Host "VM ready. Waiting for guest evidence (stall=${StallMinutes}m, wall=${WallClockMinutes}m)…"
if ($Monitor) { Start-SmokeMonitor -VmName $VmName }

$deadline = [datetime]::UtcNow.AddMinutes($WallClockMinutes)
$stallDeadline = [datetime]::UtcNow.AddMinutes($StallMinutes)
$bootNudgeUntil = [datetime]::UtcNow.AddMinutes(3)

# Local+autoLogon Profiles need explicit PS Direct credentials (workgroup guest).
$guestCred = $null
$profileDoc = $null
try {
    $profileDoc = Get-Content -LiteralPath $Profile -Raw -Encoding utf8 | ConvertFrom-Json
    $gu = [string]$profileDoc.account.username
    $gp = [string]$profileDoc.account.password
    if ($gu -and $gp) {
        $guestCred = [pscredential]::new($gu, (ConvertTo-SecureString $gp -AsPlainText -Force))
    }
}
catch {
    Write-Warning "Could not read guest credentials from Profile: $($_.Exception.Message)"
}

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
    # Prefer PowerShell Direct when available; else host-copied folder under Work.
    # Reboot evidence is not terminal — keep waiting for resume → Complete (ticket 17).
    $localReady = Get-ChildItem -Path (Join-Path $guestDir 'evidence-*.json') -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($null -ne $localReady) {
        try {
            $localDoc = Get-Content -LiteralPath $localReady.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            $localOutcome = [string]$localDoc.outcome
            if ($localOutcome -eq 'Complete' -and (Test-Path -LiteralPath (Join-Path $guestDir 'winlogon-shell.txt'))) {
                return $true
            }
            if ($localOutcome -eq 'Failed') {
                return $true
            }
            # Reboot / incomplete unlock marker — fall through and re-query guest.
        }
        catch {
            # corrupt local copy — re-query
        }
    }
    try {
        $sessionParams = @{ VMName = $VmName; ErrorAction = 'Stop' }
        if ($null -ne $guestCred) { $sessionParams['Credential'] = $guestCred }
        $session = New-PSSession @sessionParams
        try {
            # Disk is booting Windows — HDD first; eject DVD only after heartbeat (not mid-WinPE reboot).
            Prefer-DiskBoot
            Dismount-InstallDvdWhenWindowsBoots

            $remote = Invoke-Command -Session $session -ScriptBlock {
                $dir = Join-Path $env:ProgramData 'WinMint\evidence'
                if (-not (Test-Path -LiteralPath $dir)) { return $null }
                Get-ChildItem -LiteralPath $dir -Filter 'evidence-*.json' -File |
                    Sort-Object LastWriteTimeUtc -Descending |
                    Select-Object -First 1 -ExpandProperty FullName
            }
            if ($remote) {
                $leaf = Split-Path $remote -Leaf
                Copy-Item -FromSession $session -Path $remote -Destination (Join-Path $guestDir $leaf) -Force
                $pulled = Get-Content -LiteralPath (Join-Path $guestDir $leaf) -Raw -Encoding utf8 | ConvertFrom-Json
                $outcome = [string]$pulled.outcome
                if ($expectNativePackageAudit) {
                    $nativeRemote = Invoke-Command -Session $session -ScriptBlock {
                        $p = Join-Path $env:ProgramData 'WinMint\evidence\native-packages.json'
                        if (Test-Path -LiteralPath $p) { $p } else { $null }
                    }
                    if ($nativeRemote) {
                        Copy-Item -FromSession $session -Path $nativeRemote -Destination (Join-Path $guestDir 'native-packages.json') -Force
                    }
                }
                if ($outcome -eq 'Reboot') {
                    Write-Host 'Guest evidence outcome=Reboot — waiting for checkpoint resume…'
                    return $false
                }
                # Unlock prove-out: Winlogon Shell after tenure
                $shellVal = Invoke-Command -Session $session -ScriptBlock {
                    try {
                        (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name Shell -ErrorAction Stop).Shell
                    }
                    catch { $null }
                }
                if ($shellVal) {
                    Set-Content -LiteralPath (Join-Path $guestDir 'winlogon-shell.txt') -Value ([string]$shellVal).Trim() -Encoding utf8
                }
                return $true
            }
        }
        finally {
            Remove-PSSession $session -ErrorAction SilentlyContinue
        }
    }
    catch {
        # PS Direct unavailable until guest is up / integration services ready
    }
    return $false
}

$script:DiskBootPreferred = $false
$script:DvdEjected = $false
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
        return [string]$hb.PrimaryStatusDescription -eq 'OK'
    }
    catch {
        return $false
    }
}

function Prefer-DiskBoot {
    if ($script:DiskBootPreferred) { return }
    if (-not (Test-SmokeVhdHasImage)) {
        Write-Host 'Setup reboot before disk has an image — keeping install DVD attached.'
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
        # ponytail: ejecting here races WinPE wpeutil reboot → Boot Manager 0xc0000178 STATUS_NO_MEDIA.
        Write-Host 'Preferred HDD boot (install DVD attached until Windows heartbeat).'
    }
    catch {
        Write-Warning "Could not prefer disk boot: $($_.Exception.Message)"
    }
}

function Dismount-InstallDvdWhenWindowsBoots {
    if ($script:DvdEjected) { return }
    if (-not $script:DiskBootPreferred) { return }
    if (-not (Test-GuestWindowsHeartbeat)) { return }
    try {
        $dvdDev = Get-VMDvdDrive -VMName $VmName
        if ($null -ne $dvdDev -and -not [string]::IsNullOrWhiteSpace([string]$dvdDev.Path)) {
            Set-VMDvdDrive -VMName $VmName -Path $null
            Write-Host 'Ejected install DVD after Windows heartbeat.'
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
        Write-Host 'Sent Space/Enter to VM (DVD boot keypress).'
    }
    catch {
        Write-Warning "Could not send boot keypress to VM: $($_.Exception.Message)"
    }
}

Send-VmBootNudge

$wallLeft = [math]::Max(0, [int]($deadline - [datetime]::UtcNow).TotalMinutes)
try {
    while ([datetime]::UtcNow -lt $deadline) {
        if (Test-GuestEvidenceReady) {
            Write-Host 'Guest evidence pulled.'
            break
        }

        $vm = Get-VM -Name $VmName
        # Setup reboots flip Running → Stopping → Off → Starting → Running; do not fail-closed.
        # Eject DVD only after the VHD has an applied image so a WinPE reboot cannot leave an empty disk.
        switch ([string]$vm.State) {
            'Running' {
                # HDD first before wpeutil reboot. Waiting for Stopping misses the flip and
                # WinPE LaunchApply runs again (clean + apply) if DVD is still attached.
                Prefer-DiskBoot
                Dismount-InstallDvdWhenWindowsBoots
            }
            'Starting' { Write-Host 'VM Starting (setup reboot)…' }
            'Stopping' {
                Write-Host 'VM Stopping (setup reboot)…'
                Prefer-DiskBoot
            }
            'Off' {
                Write-Host 'VM Off during setup — starting again…'
                Prefer-DiskBoot
                Start-VM -Name $VmName -ErrorAction SilentlyContinue
            }
            default {
                throw "VM in unexpected state: $($vm.State)"
            }
        }

        # Heartbeat: CPU activity or setup reboot churn extends stall — idle Running does not.
        $cpu = 0
        try { $cpu = [int]$vm.CPUUsage } catch { $cpu = 0 }
        if ($cpu -gt 0 -or $vm.State -in @('Starting', 'Stopping')) {
            $stallDeadline = [datetime]::UtcNow.AddMinutes($StallMinutes)
        }

        $vhdBytes = 0
        try {
            $drive = Get-VMHardDiskDrive -VMName $VmName | Select-Object -First 1
            if ($drive) { $vhdBytes = [long](Get-VHD -Path $drive.Path).FileSize }
        } catch { $vhdBytes = 0 }
        $hb = Test-GuestWindowsHeartbeat
        $phase = Resolve-SmokePhase -HostStage wait -VmState ([string]$vm.State) `
            -VhdFileSizeBytes $vhdBytes -HeartbeatOk:$hb
        $stallLeft = [math]::Max(0, [int]($stallDeadline - [datetime]::UtcNow).TotalMinutes)
        $wallLeft = [math]::Max(0, [int]($deadline - [datetime]::UtcNow).TotalMinutes)
        Write-SmokeStatus -Path $statusPath -Phase $phase -VmName $VmName -VmState ([string]$vm.State) `
            -Cpu $cpu -Heartbeat $(if ($hb) { 'OK' } else { 'No Contact' }) `
            -VhdFileSizeMB ([int][math]::Round($vhdBytes / 1MB)) `
            -StallMinutesLeft $stallLeft -WallMinutesLeft $wallLeft `
            -LastHostLine "VM $([string]$vm.State)" -OutputIso $outIso

        if ([datetime]::UtcNow -gt $stallDeadline) {
            throw "STALL_SUSPECT: no guest evidence / CPU progress for ${StallMinutes} minutes (fail-fast before WallClockTimeout)."
        }

        # Boot nudge only while DVD is still first (before Prefer-DiskBoot).
        if (-not $script:DiskBootPreferred -and [datetime]::UtcNow -lt $bootNudgeUntil -and $vm.State -eq 'Running') {
            Send-VmBootNudge
        }

        Start-Sleep -Seconds 30
    }

    if (-not (Get-ChildItem -LiteralPath $guestDir -Filter 'evidence-*.json' -ErrorAction SilentlyContinue)) {
        throw "Wall clock elapsed without guest evidence under $guestDir"
    }

    Write-SmokeStatus -Path $statusPath -Phase (Resolve-SmokePhase -HostStage assert) `
        -VmName $VmName -StallMinutesLeft 0 -WallMinutesLeft $wallLeft `
        -LastHostLine 'Guest evidence pulled.' -OutputIso $outIso
    & $assertScript -EvidenceDir $evidenceOut `
        -PinnedRemoveAppx $pinnedRemoveAppx `
        -PinnedOnlineRemoveAppx $pinnedOnlineRemoveAppx `
        -PinnedRemoveCapabilities $pinnedRemoveCapabilities `
        -PinnedDisableOptionalFeatures $pinnedDisableOptionalFeatures `
        $(if ($expectNativePackageAudit) { '-ExpectNativePackageAudit' })
    if ($LASTEXITCODE -ne 0) { throw "Assert-SmokeEvidence exit $LASTEXITCODE" }
    Write-SmokeStatus -Path $statusPath -Phase (Resolve-SmokePhase -HostStage green) `
        -VmName $VmName -LastHostLine 'Smoke green' -OutputIso $outIso
    Write-Host "Smoke green. Evidence: $evidenceOut"
    exit 0
}
catch {
    Write-SmokeStatus -Path $statusPath -Phase (Resolve-SmokePhase -HostStage failed) `
        -VmName $VmName -LastHostLine ([string]$_.Exception.Message) -OutputIso $outIso
    throw
}
