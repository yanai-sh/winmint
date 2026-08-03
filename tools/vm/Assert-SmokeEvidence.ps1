#requires -Version 7.6
<#
.SYNOPSIS
  Assert a pulled Smoke evidence folder (S4). Pure — no Hyper-V.

.DESCRIPTION
  Expects:
    <EvidenceDir>/guest/evidence-*.json  (winmint.provisioning.evidence/v1)
    <EvidenceDir>/apply/evidence.json    (winmint.image.evidence/v1, optional lane)
  Writes <EvidenceDir>/acceptance.json summary on success.
#>
param(
    [Parameter(Mandatory)]
    [string] $EvidenceDir,

    [double] $FirstPaintBudgetSeconds = 2.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ADR-006 / samples/acceptance.profile.json — frozen acceptance remove-list.
$PinnedRemoveAppx = @('Microsoft.BingNews', 'Microsoft.GamingApp')

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
$unlockedOutcomes = @('Complete', 'Failed')
if ($unlockedOutcomes -notcontains $outcome) {
    throw "expected unlock outcome Complete|Failed, got '$outcome' (Reboot keeps Shell — not Smoke green)"
}

# DMA: hard green (settle.ok / location_warn) OR hard fail path with evidence.
# settle.skipped is not acceptance-green (acceptance Profile is DMA-on).
$dmaOk = ($phases -contains 'settle.ok') -or ($phases -contains 'settle.location_warn')
$dmaFailed = ($phases -contains 'settle.hard_mismatch') -or
    ($phases -contains 'settle.apply_failed') -or
    ($phases -contains 'settle.read_failed') -or
    ($phases -contains 'settle.target_incomplete')
if (-not $dmaOk -and -not $dmaFailed) {
    throw 'DMA settle marker missing (need settle.ok|location_warn or hard-fail phase)'
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

# Keep-flag (ticket 14 / ADR-006 B4): offline remove digests from Apply evidence.
$digestMap = @{}
if ($apply.PSObject.Properties.Name -contains 'digests' -and $null -ne $apply.digests) {
    foreach ($p in $apply.digests.PSObject.Properties) {
        $digestMap[[string]$p.Name] = [string]$p.Value
    }
}
foreach ($id in $PinnedRemoveAppx) {
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    $key = "removed.appx.$id"
    if (-not $digestMap.ContainsKey($key) -or $digestMap[$key] -ne 'absent') {
        throw "keep-flag digest missing: expected $key=absent in apply/evidence.json digests (pinned acceptance remove-list)"
    }
}

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
    $paintWarn = $true
    Write-Warning ("time-to-first-paint {0:N0} ms exceeds budget {1:N0} ms" -f $firstPaintMs, $budgetMs)
}

$acceptance = [ordered]@{
    schemaVersion           = 'winmint.smoke.acceptance/v1'
    splashBeforeExplorer    = $true
    dmaHardFields           = $(if ($dmaOk) { 'ok' } else { 'failed' })
    unlocked                = $true
    outcome                 = $outcome
    lane                    = $lane
    firstPaintMs            = $firstPaintMs
    firstPaintWarn          = $paintWarn
    keepFlagAppxAbsent      = $true
    pinnedRemoveAppx        = @($PinnedRemoveAppx)
    guestEvidencePath       = $guestPath
}
$acceptancePath = Join-Path $EvidenceDir 'acceptance.json'
$acceptance | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $acceptancePath -Encoding utf8
Write-Output "Smoke evidence OK → $acceptancePath"
exit 0
