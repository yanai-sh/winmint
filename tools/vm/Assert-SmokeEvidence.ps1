#requires -Version 7.6
<#
.SYNOPSIS
  Assert a pulled Smoke evidence folder (S4). Pure — no Hyper-V.

.DESCRIPTION
  Expects:
    <EvidenceDir>/guest/evidence-*.json  (winmint.provisioning.evidence/v1)
    <EvidenceDir>/apply/evidence.json    (winmint.image.evidence/v1, optional lane)
    <EvidenceDir>/guest/winlogon-shell.txt  (Winlogon Shell after tenure — must be explorer.exe)
  Writes <EvidenceDir>/acceptance.json summary on success.
#>
param(
    [Parameter(Mandatory)]
    [string] $EvidenceDir,

    [double] $FirstPaintBudgetSeconds = 2.0,

    # Ticket 30 / hardware M4: stricter bars — firstPaint fail (not warn); settle.ok|location_warn only.
    [switch] $HardwareM4,

    # Empty ⇒ skip keep-flag digest asserts (israel/smoke Profiles without remove-list).
    # Default = acceptance pins when AssertOnly without an explicit list.
    [string[]] $PinnedRemoveAppx = @('Microsoft.BingNews', 'Microsoft.BingWeather'),

    # Ticket 19/20 thin acceptance pins (samples/acceptance.profile.json). Empty ⇒ skip.
    [string[]] $PinnedRemoveCapabilities = @('App.StepsRecorder~~~~0.0.1.0', 'WMIC~~~~'),

    [string[]] $PinnedDisableOptionalFeatures = @('WorkFolders-Client')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hardwareM4 = $HardwareM4.IsPresent -or ($env:WINMINT_M4 -eq '1')

# ADR-006 / samples/acceptance.profile.json — frozen acceptance remove-list when caller omits -PinnedRemoveAppx.
# Re-pin if acceptance Source ISO churn drops an id (KEEPFLAG).
$ExplorerShell = 'explorer.exe'
$SupervisorShellLeaf = 'Supervisor.exe'

function Get-LatestGuestEvidence {
    param([string] $Dir)
    $guest = Join-Path $Dir 'guest'
    if (-not (Test-Path -LiteralPath $guest)) {
        throw "guest evidence folder missing: $guest"
    }
    $files = Get-ChildItem -LiteralPath $guest -Filter 'evidence-*.json' -File |
        Sort-Object LastWriteTimeUtc -Descending
    if (-not $files) {
        throw "no guest evidence-*.json under $guest"
    }
    return $files[0].FullName
}

function Read-JsonFile {
    param([string] $Path)
    return (Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json)
}

$guestPath = Get-LatestGuestEvidence -Dir $EvidenceDir
$guest = Read-JsonFile -Path $guestPath

if ($guest.schemaVersion -ne 'winmint.provisioning.evidence/v1') {
    throw "unexpected guest schema '$($guest.schemaVersion)'"
}

$phases = @($guest.phases)
if ($phases -notcontains 'shell.first_paint') {
    throw 'splash-before-Explorer marker missing: phases must contain shell.first_paint'
}

$paintIdx = [array]::IndexOf($phases, 'shell.first_paint')
$settleIdx = [array]::IndexOf($phases, 'settle.begin')
if ($settleIdx -ge 0 -and $paintIdx -gt $settleIdx) {
    throw 'splash-before-Explorer failed: shell.first_paint after settle.begin'
}

$outcome = [string]$guest.outcome
if ($outcome -ne 'Complete') {
    throw "Smoke acceptance requires outcome Complete, got '$outcome' (Failed/Reboot is not green)"
}

# DMA hard fields must succeed — apply_failed / hard_mismatch are not acceptance-green.
# M4 (hardware): settle.ok or settle.location_warn only — no resume_skip shortcut.
# Default: resume_skip + checkpoint.resume also proves prior settle (ticket 17).
$dmaOk = if ($hardwareM4) {
    ($phases -contains 'settle.ok') -or ($phases -contains 'settle.location_warn')
} else {
    ($phases -contains 'settle.ok') -or ($phases -contains 'settle.location_warn') -or
        (($phases -contains 'settle.resume_skip') -and ($phases -contains 'checkpoint.resume'))
}
if (-not $dmaOk) {
    $need = if ($hardwareM4) { 'settle.ok or settle.location_warn (M4)' } else { 'settle.ok, settle.location_warn, or settle.resume_skip+checkpoint.resume' }
    throw "DMA hard fields missing: need $need"
}

# Unlock: Winlogon Shell must be Explorer, not Supervisor.
$shellPath = Join-Path $EvidenceDir 'guest\winlogon-shell.txt'
if (-not (Test-Path -LiteralPath $shellPath)) {
    throw "unlock marker missing: expected guest/winlogon-shell.txt (Winlogon Shell after tenure)"
}
$shell = ([string](Get-Content -LiteralPath $shellPath -Raw -Encoding utf8)).Trim()
if ([string]::IsNullOrWhiteSpace($shell)) {
    throw 'unlock marker empty: guest/winlogon-shell.txt'
}
if ($shell -like "*$SupervisorShellLeaf") {
    throw "unlock failed: Winlogon Shell still Supervisor ('$shell')"
}
if (-not ($shell.Equals($ExplorerShell, [System.StringComparison]::OrdinalIgnoreCase) -or
        $shell.EndsWith("\$ExplorerShell", [System.StringComparison]::OrdinalIgnoreCase))) {
    throw "unlock failed: expected explorer.exe, got '$shell'"
}

$lane = $null
$applyEvidence = Join-Path $EvidenceDir 'apply\evidence.json'
if (-not (Test-Path -LiteralPath $applyEvidence)) {
    throw "lane marker missing: expected apply/evidence.json under $EvidenceDir"
}
$apply = Read-JsonFile -Path $applyEvidence
if ($apply.PSObject.Properties.Name -contains 'lane' -and $apply.lane) {
    $lane = [string]$apply.lane
}
if (-not $lane) {
    throw 'lane marker missing (apply/evidence.json must include lane)'
}
if ($lane -notin @('Test', 'Release')) {
    throw "lane marker must be Test|Release, got '$lane'"
}

# Keep-flag (ticket 14 / ADR-006 B4): offline remove digests from Apply evidence when Profile pins any.
$digestMap = @{}
if ($apply.PSObject.Properties.Name -contains 'digests' -and $null -ne $apply.digests) {
    foreach ($p in $apply.digests.PSObject.Properties) {
        $digestMap[[string]$p.Name] = [string]$p.Value
    }
}

function Assert-PinnedDigests {
    param(
        [string[]] $Ids,
        [string] $KeyPrefix,
        [string] $ExpectedValue,
        [string] $Label
    )
    if ($null -eq $Ids -or @($Ids).Count -eq 0) { return $false }
    foreach ($id in $Ids) {
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $key = "$KeyPrefix$id"
        if (-not $digestMap.ContainsKey($key) -or $digestMap[$key] -ne $ExpectedValue) {
            throw "keep-flag digest missing: expected $key=$ExpectedValue in apply/evidence.json digests ($Label)"
        }
    }
    return $true
}

$keepFlagChecked = Assert-PinnedDigests -Ids $PinnedRemoveAppx -KeyPrefix 'removed.appx.' -ExpectedValue 'absent' -Label 'appx'
$capsChecked = Assert-PinnedDigests -Ids $PinnedRemoveCapabilities -KeyPrefix 'removed.capability.' -ExpectedValue 'Absent' -Label 'capability'
$featsChecked = Assert-PinnedDigests -Ids $PinnedDisableOptionalFeatures -KeyPrefix 'disabled.feature.' -ExpectedValue 'Disabled' -Label 'feature'

$firstPaintMs = $null
if ($guest.PSObject.Properties.Name -contains 'firstPaintMs' -and $null -ne $guest.firstPaintMs) {
    $firstPaintMs = [double]$guest.firstPaintMs
}
if ($null -eq $firstPaintMs) {
    throw 'firstPaintMs missing on guest evidence (S4 must record time-to-first-paint)'
}
$paintWarn = $false
$budgetMs = $FirstPaintBudgetSeconds * 1000.0
if ($firstPaintMs -gt $budgetMs) {
    if ($hardwareM4) {
        throw ("M4: time-to-first-paint {0:N0} ms exceeds budget {1:N0} ms" -f $firstPaintMs, $budgetMs)
    }
    $paintWarn = $true
    Write-Warning ("time-to-first-paint {0:N0} ms exceeds budget {1:N0} ms" -f $firstPaintMs, $budgetMs)
}

$acceptance = [ordered]@{
    schemaVersion           = 'winmint.smoke.acceptance/v1'
    splashBeforeExplorer    = $true
    dmaHardFields           = 'ok'
    unlocked                = $true
    outcome                 = $outcome
    lane                    = $lane
    firstPaintMs            = $firstPaintMs
    firstPaintWarn          = $paintWarn
    hardwareM4              = $hardwareM4
    keepFlagAppxAbsent      = $keepFlagChecked
    keepFlagCapsAbsent      = $capsChecked
    keepFlagFeaturesDisabled = $featsChecked
    pinnedRemoveAppx        = @($PinnedRemoveAppx)
    pinnedRemoveCapabilities = @($PinnedRemoveCapabilities)
    pinnedDisableOptionalFeatures = @($PinnedDisableOptionalFeatures)
    winlogonShell           = $shell
    guestEvidencePath       = $guestPath
}
$acceptancePath = Join-Path $EvidenceDir 'acceptance.json'
$acceptance | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $acceptancePath -Encoding utf8
Write-Output "Smoke evidence OK → $acceptancePath"
exit 0
