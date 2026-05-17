#Requires -Version 7.3
<#
<summary>
    Audit-RunCaptures.ps1 — drive the running WinWS wizard through every page
    with realistic test fixtures (input/*.iso, input/*.msi) and snapshot each
    state. Output is a list of PNGs in output/screenshots/ ready for visual
    review.

    Prerequisite: WinMint-UI.ps1 already running at Page 0 (Source) in the same
    admin shell. The script will not relaunch the wizard.

    Usage:
        pwsh -NoProfile -File scripts\ui-automation\Audit-RunCaptures.ps1
        pwsh -NoProfile -File scripts\ui-automation\Audit-RunCaptures.ps1 -SkipDriver  # if no input/*.msi

    Fails fast if WinWS isn't running, the ISO doesn't verify within 60s, or
    Drive-Ui.ps1 returns a non-zero exit on any verb.
</summary>
#>

[CmdletBinding()]
param(
    [switch]$SkipDriver,
    [int]$VerifyTimeoutSec = 60,
    [string]$DonePath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repoRoot    = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$drivePath   = Join-Path $repoRoot 'scripts\ui-automation\Drive-Ui.ps1'
$captureDir   = Join-Path $repoRoot 'output\screenshots'
$snapshotsDir = Join-Path $repoRoot 'output\ui-snapshots'
$auditPwshExe = (Get-Process -Id $PID).Path

function Complete-AuditRun {
    param(
        [Parameter(Mandatory)][ValidateSet('ok', 'failed')][string]$Status,
        [string]$Message = ''
    )
    if ([string]::IsNullOrWhiteSpace($DonePath)) { return }
    $doneDir = Split-Path -Parent $DonePath
    if (-not [string]::IsNullOrWhiteSpace($doneDir)) {
        $null = New-Item -ItemType Directory -Path $doneDir -Force -ErrorAction SilentlyContinue
    }
    [pscustomobject]@{
        status    = $Status
        message   = $Message
        completed = (Get-Date).ToString('o')
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath $DonePath -Encoding UTF8
}

trap {
    Complete-AuditRun -Status failed -Message $_.Exception.Message
    throw
}

function Invoke-Drive {
    param([Parameter(Mandatory)][string[]]$DriveArgs)
    $output = & $auditPwshExe -NoProfile -File $drivePath @DriveArgs 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0) {
        Write-Error "Drive-Ui.ps1 failed (exit $exit) for: $($DriveArgs -join ' ')`n$output"
    }
    try { return ($output | Select-Object -Last 1 | ConvertFrom-Json) }
    catch { return $output }
}

Write-Host "=== Audit capture sweep ===" -ForegroundColor Cyan

# Clear prior captures so each sweep is a clean record (semantic JSON is primary; PNG optional).
if (Test-Path -LiteralPath $snapshotsDir) {
    Get-ChildItem -LiteralPath $snapshotsDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "Cleared prior UI snapshots in $snapshotsDir"
}
if (Test-Path -LiteralPath $captureDir) {
    Get-ChildItem -LiteralPath $captureDir -Filter '*.png' -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "Cleared prior PNGs in $captureDir"
}

# Clear the system clipboard. A stale FileDropList from a prior audit (or any
# Explorer copy) would race the Browse handler via Window.Activated and mask
# whether the Browse buttons themselves still work.
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    [System.Windows.Forms.Clipboard]::Clear()
    Write-Host "Cleared system clipboard"
} catch {
    Write-Host "Clipboard clear skipped: $_"
}

# Verify WinWS is up.
$state = Invoke-Drive -DriveArgs @('-Action', 'GetUiState')
Write-Host "Initial state: page=$($state.page) isoVerified=$($state.isoVerified)"

# 1. Page 0 — idle (no ISO loaded yet, if applicable)
if (-not $state.isoVerified) {
    Invoke-Drive -DriveArgs @('-Action', 'Snapshot', '-Label', 'page0-idle') | Out-Null
    Write-Host "  snapshot: page0-idle (output/ui-snapshots/*.json)"
}

# 2. Load ISO (auto from input/) and wait for verification
Write-Host "Loading ISO from input/..."
Invoke-Drive -DriveArgs @('-Action', 'SetIso') | Out-Null

# DISM verification runs in a ThreadJob (~10s). UIA reads can blip during that
# window — tolerate transient probe failures rather than killing the sweep.
$deadline   = (Get-Date).AddSeconds($VerifyTimeoutSec)
$verified   = $false
do {
    Start-Sleep -Milliseconds 800
    try {
        $state    = Invoke-Drive -DriveArgs @('-Action', 'GetUiState')
        $verified = [bool]$state.isoVerified
    } catch {
        Write-Host "  (probe transient: $($_.Exception.Message.Split([char]10)[0]))"
    }
} while ((-not $verified) -and (Get-Date) -lt $deadline)
if (-not $verified) {
    Write-Error "ISO did not verify within ${VerifyTimeoutSec}s."
}
Write-Host "  ISO verified."

# 3. Page 0 — verified state
Invoke-Drive -DriveArgs @('-Action', 'Snapshot', '-Label', 'page0-verified') | Out-Null
Write-Host "  snapshot: page0-verified"

# 4. Page 1 — Machine (target, edition, drivers)
Invoke-Drive -DriveArgs @('-Action', 'GoToPage', '-Page', '1') | Out-Null
Start-Sleep -Milliseconds 400
Invoke-Drive -DriveArgs @('-Action', 'Snapshot', '-Label', 'page1-machine-defaults') | Out-Null
Write-Host "  snapshot: page1-machine-defaults"

if (-not $SkipDriver) {
    Write-Host "Loading driver MSI from input/..."
    try {
        Invoke-Drive -DriveArgs @('-Action', 'SetDriver') | Out-Null
        Start-Sleep -Milliseconds 500
        Invoke-Drive -DriveArgs @('-Action', 'Snapshot', '-Label', 'page1-machine-custom-driver') | Out-Null
        Write-Host "  snapshot: page1-machine-custom-driver"
    } catch {
        Write-Warning "SetDriver failed; continuing without driver-loaded snapshot. $_"
    }
}

# 5. Page 2 — Disk behavior
Invoke-Drive -DriveArgs @('-Action', 'GoToPage', '-Page', '2') | Out-Null
Start-Sleep -Milliseconds 400
Invoke-Drive -DriveArgs @('-Action', 'Snapshot', '-Label', 'page2-disk-defaults') | Out-Null
Write-Host "  snapshot: page2-disk-defaults"

# Also capture the destructive option on the dedicated Disk page.
Invoke-Drive -DriveArgs @('-Action', 'Click', '-Name', 'RbDiskAuto') | Out-Null
Start-Sleep -Milliseconds 250
Invoke-Drive -DriveArgs @('-Action', 'Snapshot', '-Label', 'page2-disk-auto-erase') | Out-Null
Write-Host "  snapshot: page2-disk-auto-erase"

Invoke-Drive -DriveArgs @('-Action', 'SetCheck', '-Name', 'ChkDiskWipeConfirm', '-Value', 'true') | Out-Null
Start-Sleep -Milliseconds 250
Invoke-Drive -DriveArgs @('-Action', 'Snapshot', '-Label', 'page2-disk-auto-erase-confirmed') | Out-Null
Write-Host "  snapshot: page2-disk-auto-erase-confirmed"

# Restore manual to keep the rest of the run safe.
Invoke-Drive -DriveArgs @('-Action', 'Click', '-Name', 'RbDiskManual') | Out-Null
Start-Sleep -Milliseconds 200

# 6. Page 3 — Identity
Invoke-Drive -DriveArgs @('-Action', 'GoToPage', '-Page', '3') | Out-Null
Start-Sleep -Milliseconds 400
Invoke-Drive -DriveArgs @('-Action', 'Snapshot', '-Label', 'page3-identity-passwordless') | Out-Null
Write-Host "  snapshot: page3-identity-passwordless"
Invoke-Drive -DriveArgs @('-Action', 'SetText', '-Name', 'TxtComputerName', '-Value', 'WINWS-LAB-PC') | Out-Null
Invoke-Drive -DriveArgs @('-Action', 'SetText', '-Name', 'TxtAccountName', '-Value', 'yanai') | Out-Null
Start-Sleep -Milliseconds 250
Invoke-Drive -DriveArgs @('-Action', 'Snapshot', '-Label', 'page3-identity-filled') | Out-Null
Write-Host "  snapshot: page3-identity-filled"

# 7. Page 4 — Workstation
Invoke-Drive -DriveArgs @('-Action', 'GoToPage', '-Page', '4') | Out-Null
Start-Sleep -Milliseconds 400
Invoke-Drive -DriveArgs @('-Action', 'Snapshot', '-Label', 'page4-workstation-defaults') | Out-Null
Write-Host "  snapshot: page4-workstation-defaults"
Invoke-Drive -DriveArgs @('-Action', 'Click', '-Name', 'ChkShellWindhawk') | Out-Null
Invoke-Drive -DriveArgs @('-Action', 'Click', '-Name', 'ChkShellYasb') | Out-Null
Invoke-Drive -DriveArgs @('-Action', 'Click', '-Name', 'ChkShellKomorebi') | Out-Null
Invoke-Drive -DriveArgs @('-Action', 'Click', '-Name', 'ChkWslDebian') | Out-Null
Invoke-Drive -DriveArgs @('-Action', 'Click', '-Name', 'ChkWslArch') | Out-Null
Invoke-Drive -DriveArgs @('-Action', 'Click', '-Name', 'ChkWslFedora') | Out-Null
Invoke-Drive -DriveArgs @('-Action', 'Click', '-Name', 'ChkEditorZed') | Out-Null
Start-Sleep -Milliseconds 250
Invoke-Drive -DriveArgs @('-Action', 'Snapshot', '-Label', 'page4-workstation-expanded') | Out-Null
Write-Host "  snapshot: page4-workstation-expanded"

# 8. Page 5 — Launch
Invoke-Drive -DriveArgs @('-Action', 'GoToPage', '-Page', '5') | Out-Null
Start-Sleep -Milliseconds 500
Invoke-Drive -DriveArgs @('-Action', 'Snapshot', '-Label', 'page5-launch') | Out-Null
Write-Host "  snapshot: page5-launch"

Write-Host ""
Write-Host "=== Done. UI automation snapshots (primary) in $snapshotsDir ===" -ForegroundColor Cyan
Get-ChildItem -LiteralPath $snapshotsDir -Filter '*.json' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 20 |
    ForEach-Object { Write-Host "  $($_.FullName)" }
Write-Host "Optional PNGs (if any) under $captureDir"

Complete-AuditRun -Status ok
