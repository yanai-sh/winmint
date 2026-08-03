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
    [int] $StallMinutes = 15,

    [Parameter(ParameterSetName = 'Run')]
    [int] $WallClockMinutes = 90,

    [Parameter(ParameterSetName = 'Run')]
    [switch] $SkipApply,

    [Parameter(Mandatory, ParameterSetName = 'AssertOnly')]
    [switch] $AssertOnly,

    [Parameter(Mandatory, ParameterSetName = 'AssertOnly')]
    [string] $EvidenceDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $repoRoot

function Invoke-AssertSmokeEvidence {
    param([string] $Dir)
    $assert = Join-Path $PSScriptRoot 'Assert-SmokeEvidence.ps1'
    & $assert -EvidenceDir $Dir
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if ($AssertOnly) {
    Invoke-AssertSmokeEvidence -Dir $EvidenceDir
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
Write-Host "Preparing VM $VmName…"
if (Get-VM -Name $VmName -ErrorAction SilentlyContinue) {
    Stop-VM -Name $VmName -TurnOff -Force -ErrorAction SilentlyContinue
    Remove-VM -Name $VmName -Force
}
if (Test-Path -LiteralPath $vhdx) { Remove-Item -LiteralPath $vhdx -Force }

# Gen2, Secure Boot off for lab ISOs without vTPM (SPLASH spike lesson).
New-VHD -Path $vhdx -SizeBytes 64GB -Dynamic | Out-Null
New-VM -Name $VmName -Generation 2 -MemoryStartupBytes 4GB -VHDPath $vhdx | Out-Null
Set-VMFirmware -VMName $VmName -EnableSecureBoot Off
Set-VMProcessor -VMName $VmName -Count 4
# DVD boot from applied ISO
$dvd = Get-VMDvdDrive -VMName $VmName -ErrorAction SilentlyContinue
if (-not $dvd) {
    Add-VMDvdDrive -VMName $VmName -Path $outIso
}
else {
    Set-VMDvdDrive -VMName $VmName -Path $outIso
}
# Boot from DVD first
$fw = Get-VMFirmware -VMName $VmName
$dvdDev = Get-VMDvdDrive -VMName $VmName
Set-VMFirmware -VMName $VmName -FirstBootDevice $dvdDev

# Hyper-V media ACL (SPLASH spike)
$aclRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    'NT VIRTUAL MACHINE\Virtual Machines', 'Read', 'Allow')
foreach ($media in @($outIso, $vhdx)) {
    $acl = Get-Acl -LiteralPath $media
    $acl.AddAccessRule($aclRule)
    Set-Acl -LiteralPath $media -AclObject $acl
}

Start-VM -Name $VmName
Write-Host "VM started. Waiting for guest evidence (stall=${StallMinutes}m, wall=${WallClockMinutes}m)…"

$deadline = [datetime]::UtcNow.AddMinutes($WallClockMinutes)
$stallDeadline = [datetime]::UtcNow.AddMinutes($StallMinutes)

function Test-GuestEvidenceReady {
    # Prefer PowerShell Direct when available; else host-copied folder under Work.
    $copied = Join-Path $guestDir 'evidence-*.json'
    if (Get-ChildItem -Path $copied -ErrorAction SilentlyContinue) { return $true }
    try {
        $session = New-PSSession -VMName $VmName -ErrorAction Stop
        try {
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
                $remoteLog = 'C:\ProgramData\WinMint\shell.log'
                $logExists = Invoke-Command -Session $session -ScriptBlock {
                    param($p) Test-Path -LiteralPath $p
                } -ArgumentList $remoteLog
                if ($logExists) {
                    Copy-Item -FromSession $session -Path $remoteLog -Destination (Join-Path $guestDir 'shell.log') -Force -ErrorAction SilentlyContinue
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

while ([datetime]::UtcNow -lt $deadline) {
    if (Test-GuestEvidenceReady) {
        Write-Host 'Guest evidence pulled.'
        break
    }

    if ([datetime]::UtcNow -gt $stallDeadline) {
        throw "STALL_SUSPECT: no guest evidence progress for ${StallMinutes} minutes (fail-fast before WallClockTimeout)."
    }

    # Heartbeat: VM Running counts as weak progress until first evidence
    $vm = Get-VM -Name $VmName
    if ($vm.State -ne 'Running') {
        throw "VM left Running state: $($vm.State)"
    }

    Start-Sleep -Seconds 30
}

if (-not (Get-ChildItem -LiteralPath $guestDir -Filter 'evidence-*.json' -ErrorAction SilentlyContinue)) {
    throw "Wall clock elapsed without guest evidence under $guestDir"
}

Invoke-AssertSmokeEvidence -Dir $evidenceOut
Write-Host "Smoke green. Evidence: $evidenceOut"
exit 0
