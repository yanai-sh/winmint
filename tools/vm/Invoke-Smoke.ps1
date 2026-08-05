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

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $repoRoot

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

$outIso = Join-Path $Work 'out.iso'
if (-not $SkipApply) {
    Write-Host 'Publishing Supervisor (Release AOT)…'
    & just publish-provisioning
    if ($LASTEXITCODE -ne 0) { throw "just publish-provisioning failed: $LASTEXITCODE" }

    Write-Host "Applying Profile=$Profile Iso=$Iso Work=$Work (Test lane)…"
    & just apply-maintainer $Iso $Work $Profile
    if ($LASTEXITCODE -ne 0) { throw "Apply failed: $LASTEXITCODE" }
}

if (-not (Test-Path -LiteralPath $outIso)) {
    throw "Output ISO missing: $outIso (run Apply or omit -SkipApply)"
}

# Lane marker from Apply evidence (fail closed — do not invent).
$applyEvidence = Join-Path $Work 'evidence.json'
if (-not (Test-Path -LiteralPath $applyEvidence)) {
    throw "Apply evidence.json missing under $Work (lane marker required for S4)"
}
Copy-Item -LiteralPath $applyEvidence -Destination (Join-Path $applyDir 'evidence.json') -Force

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
        Remove-VM -Name $VmName -Force
    }
    # Dynamic VHD may be renamed by Hyper-V; clear any smoke*.vhdx under Work.
    Get-ChildItem -LiteralPath $Work -Filter 'smoke*.vhdx' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $Work -Filter 'smoke_*.avhdx' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $vhdx) { Remove-Item -LiteralPath $vhdx -Force }

    # Gen2, Secure Boot off + no vTPM (Start-VM times out with vTPM on this host — SPLASH).
    # Win11 setup needs LabConfig on boot.wim (patched into media before BuildIso / SkipApply).
    New-VHD -Path $vhdx -SizeBytes 64GB -Dynamic | Out-Null
    New-VM -Name $VmName -Generation 2 -MemoryStartupBytes 4GB -VHDPath $vhdx | Out-Null
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
try {
    if ($null -ne $profileDoc.packages -and $null -ne $profileDoc.packages.winget) {
        $wingetIds = @($profileDoc.packages.winget | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        $expectNativePackageAudit = $wingetIds.Count -gt 0
    }
}
catch {
    Write-Warning "Could not read Profile packages.winget: $($_.Exception.Message)"
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

function Get-StageParamIds {
    param(
        [Parameter(Mandatory)] $StagesDoc,
        [Parameter(Mandatory)] [string] $Opcode,
        [Parameter(Mandatory)] [string] $ParamName
    )
    $stage = @($StagesDoc.stages) |
        Where-Object { [string]$_.opcode -eq $Opcode } |
        Select-Object -First 1
    if ($null -eq $stage) { return @() }
    $joined = [string]$stage.parameters.$ParamName
    if ([string]::IsNullOrWhiteSpace($joined)) { return @() }
    return @(
        $joined.Split(
            ';',
            [System.StringSplitOptions]::RemoveEmptyEntries -bor [System.StringSplitOptions]::TrimEntries)
    )
}

$pinnedRemoveAppx = @(Get-StageParamIds -StagesDoc $stagesDoc -Opcode 'RemoveProvisionedAppx' -ParamName 'packageFamilyNames')
$pinnedRemoveCapabilities = @(Get-StageParamIds -StagesDoc $stagesDoc -Opcode 'RemoveCapabilities' -ParamName 'capabilityNames')
$pinnedDisableOptionalFeatures = @(Get-StageParamIds -StagesDoc $stagesDoc -Opcode 'DisableOptionalFeatures' -ParamName 'featureNames')

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
            # Disk is booting Windows — prefer HDD and eject install ISO (avoid re-Setup).
            Prefer-DiskBoot

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
function Prefer-DiskBoot {
    if ($script:DiskBootPreferred) { return }
    try {
        $hddDev = Get-VMHardDiskDrive -VMName $VmName | Select-Object -First 1
        $dvdDev = Get-VMDvdDrive -VMName $VmName
        if ($null -eq $hddDev) { return }
        if ($null -ne $dvdDev) {
            Set-VMFirmware -VMName $VmName -BootOrder $hddDev, $dvdDev
            Set-VMDvdDrive -VMName $VmName -Path $null
        }
        else {
            Set-VMFirmware -VMName $VmName -BootOrder $hddDev
        }
        $script:DiskBootPreferred = $true
        Write-Host 'Preferred HDD boot and ejected install DVD.'
    }
    catch {
        Write-Warning "Could not prefer disk boot: $($_.Exception.Message)"
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

while ([datetime]::UtcNow -lt $deadline) {
    if (Test-GuestEvidenceReady) {
        Write-Host 'Guest evidence pulled.'
        break
    }

    $vm = Get-VM -Name $VmName
    # Setup reboots flip Running → Stopping → Off → Starting → Running; do not fail-closed.
    # Prefer HDD+eject DVD on first setup reboot (not only at PS Direct) so efisys_noprompt
    # cannot re-enter Setup against a half-installed disk.
    switch ([string]$vm.State) {
        'Running' { }
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

& $assertScript -EvidenceDir $evidenceOut `
    -PinnedRemoveAppx $pinnedRemoveAppx `
    -PinnedRemoveCapabilities $pinnedRemoveCapabilities `
    -PinnedDisableOptionalFeatures $pinnedDisableOptionalFeatures `
    $(if ($expectNativePackageAudit) { '-ExpectNativePackageAudit' })
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Smoke green. Evidence: $evidenceOut"
exit 0
