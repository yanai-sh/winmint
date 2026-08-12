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

    # Empty ⇒ skip keep-flag digest asserts. Full Smoke run passes Profile remove-lists.
    [string[]] $PinnedRemoveAppx = @(),

    # Online debloat: assert guest phase removed.appx.online.{id} instead of offline apply digest.
    [string[]] $PinnedOnlineRemoveAppx = @(),

    [string[]] $PinnedRemoveCapabilities = @(),

    [string[]] $PinnedDisableOptionalFeatures = @(),

    [switch] $ExpectNativePackageAudit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

$guestPath = Get-LatestGuestEvidence -Dir $EvidenceDir
$guest = Get-Content -LiteralPath $guestPath -Raw -Encoding utf8 | ConvertFrom-Json

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

# DMA hard fields must succeed — apply_failed / hard_mismatch / device_region_failed are not acceptance-green.
# resume_skip + checkpoint.resume also proves prior settle (ticket 17), including setup-region gate on resume.
$dmaOk = ($phases -contains 'settle.ok') -or ($phases -contains 'settle.location_warn') -or
    (($phases -contains 'settle.resume_skip') -and ($phases -contains 'checkpoint.resume'))
if (-not $dmaOk) {
    throw 'DMA hard fields missing: need settle.ok, settle.location_warn, or settle.resume_skip+checkpoint.resume'
}

$setupRegionOk = ($phases -contains 'settle.device_region_ok') -or ($phases -contains 'settle.device_region_repaired')
if (-not $setupRegionOk) {
    throw 'DMA setup region missing: need settle.device_region_ok or settle.device_region_repaired (DeviceRegion Ireland)'
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
$apply = Get-Content -LiteralPath $applyEvidence -Raw -Encoding utf8 | ConvertFrom-Json
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
    if ($null -eq $Ids -or @($Ids).Count -eq 0) { return }
    foreach ($id in $Ids) {
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $key = "$KeyPrefix$id"
        if (-not $digestMap.ContainsKey($key) -or $digestMap[$key] -ne $ExpectedValue) {
            throw "keep-flag digest missing: expected $key=$ExpectedValue in apply/evidence.json digests ($Label)"
        }
    }
}

Assert-PinnedDigests -Ids $PinnedRemoveAppx -KeyPrefix 'removed.appx.' -ExpectedValue 'absent' -Label 'appx'
if (@($PinnedOnlineRemoveAppx).Count -gt 0) {
    $phaseList = @($guest.phases)
    foreach ($id in $PinnedOnlineRemoveAppx) {
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $phase = "removed.appx.online.$id"
        if ($phaseList -notcontains $phase) {
            throw "online debloat phase missing: expected guest phases to contain '$phase'"
        }
    }
}
Assert-PinnedDigests -Ids $PinnedRemoveCapabilities -KeyPrefix 'removed.capability.' -ExpectedValue 'Absent' -Label 'capability'
Assert-PinnedDigests -Ids $PinnedDisableOptionalFeatures -KeyPrefix 'disabled.feature.' -ExpectedValue 'Disabled' -Label 'feature'

$firstPaintMs = $null
if ($guest.PSObject.Properties.Name -contains 'firstPaintMs' -and $null -ne $guest.firstPaintMs) {
    $firstPaintMs = [double]$guest.firstPaintMs
}
if ($null -eq $firstPaintMs) {
    throw 'firstPaintMs missing on guest evidence (S4 must record time-to-first-paint)'
}
$budgetMs = $FirstPaintBudgetSeconds * 1000.0
if ($firstPaintMs -gt $budgetMs) {
    Write-Warning ("time-to-first-paint {0:N0} ms exceeds budget {1:N0} ms" -f $firstPaintMs, $budgetMs)
}

if ($ExpectNativePackageAudit) {
    $nativePath = Join-Path $EvidenceDir 'guest\native-packages.json'
    if (-not (Test-Path -LiteralPath $nativePath)) {
        throw "native package audit missing: expected guest/native-packages.json (Profile had winget packages)"
    }
    $native = Get-Content -LiteralPath $nativePath -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string]$native.schemaVersion -ne 'winmint.native-packages/v1') {
        throw "unexpected native audit schema '$($native.schemaVersion)'"
    }
    if ($null -eq $native.packages -or @($native.packages).Count -eq 0) {
        throw 'native-packages.json must list at least one audited package'
    }
}

$acceptance = [ordered]@{
    schemaVersion        = 'winmint.smoke.acceptance/v1'
    splashBeforeExplorer = $true
    outcome              = $outcome
    lane                 = $lane
}
$acceptancePath = Join-Path $EvidenceDir 'acceptance.json'
$acceptance | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $acceptancePath -Encoding utf8
Write-Output "Smoke evidence OK → $acceptancePath"
exit 0
