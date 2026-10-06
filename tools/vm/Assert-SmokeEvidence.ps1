#requires -Version 7.6
<#
.SYNOPSIS
  Assert a pulled Smoke evidence folder (S4). Pure — no Hyper-V.

.DESCRIPTION
  Expects:
    <EvidenceDir>/guest/evidence-*.json  (winmint.provisioning.evidence/v1)
    <EvidenceDir>/apply/evidence.json    (winmint.image.evidence/v1, optional lane)
    <EvidenceDir>/guest/winlogon-shell.txt  (Winlogon Shell after tenure — must be explorer.exe)
    <EvidenceDir>/guest/shell-chrome.json   (winmint.shell.chrome/v1 — wallpaper, pins, quiet DWords)
  Writes <EvidenceDir>/acceptance.json summary on success.
#>
param(
    [Parameter(Mandatory)]
    [string] $EvidenceDir,

    [double] $FirstPaintBudgetSeconds = 2.0,

    # Empty ⇒ skip keep-flag digest asserts. Full Smoke run passes Profile remove-lists.
    [string[]] $PinnedRemoveAppx = @(),

    # Online debloat: a live remove (removed.appx.online.{id}) or a deprovision mark
    # (package already absent on the image) both satisfy the pin.
    [string[]] $PinnedOnlineRemoveAppx = @(),

    [string[]] $PinnedRemoveCapabilities = @(),

    [string[]] $PinnedDisableOptionalFeatures = @(),

    [switch] $ExpectNativePackageAudit,

    # Full Smoke: live Winlogon Shell from the successful wait poll.
    [string] $LiveShell = '',

    [bool] $SupervisorRunning = $false,

    # Full Smoke: bind guest Evidence to this run (optional on StaticEvidenceOnly).
    [string] $RequiredSmokeRunId = '',

    # AssertOnly / fixtures: file marker only — not live FirstLogon truth.
    [switch] $StaticEvidenceOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'SmokeStatus.ps1')
. (Join-Path $PSScriptRoot '..\host\Assert-ImageEvidenceCore.ps1')

if (-not $StaticEvidenceOnly -and [string]::IsNullOrWhiteSpace($LiveShell)) {
    throw 'Assert-SmokeEvidence requires -LiveShell (full Smoke) or -StaticEvidenceOnly (AssertOnly/fixtures)'
}

function Get-LatestGuestEvidence {
    param([string] $Dir, [string] $RequiredSmokeRunId = '')
    $guest = Join-Path $Dir 'guest'
    if (-not (Test-Path -LiteralPath $guest)) {
        throw "guest evidence folder missing: $guest"
    }
    $hit = Select-WinMintGuestEvidencePath -Directory $guest -RequiredSmokeRunId $RequiredSmokeRunId
    if ([string]::IsNullOrWhiteSpace($hit)) {
        throw "no Complete/Failed guest evidence-*.json under $guest"
    }
    return $hit
}

$selectRunId = if ($StaticEvidenceOnly) { '' } else { $RequiredSmokeRunId }
$guestPath = Get-LatestGuestEvidence -Dir $EvidenceDir -RequiredSmokeRunId $selectRunId
$guest = Get-Content -LiteralPath $guestPath -Raw -Encoding utf8 | ConvertFrom-Json

if ($guest.schemaVersion -ne 'winmint.provisioning.evidence/v1') {
    throw "unexpected guest schema '$($guest.schemaVersion)'"
}

$phases = @($guest.phases)
if ($phases -notcontains 'shell.firstPaint') {
    throw 'splash-before-Explorer marker missing: phases must contain shell.firstPaint'
}

$paintIdx = [array]::IndexOf($phases, 'shell.firstPaint')
$settleIdx = [array]::IndexOf($phases, 'settle.begin')
if ($settleIdx -ge 0 -and $paintIdx -gt $settleIdx) {
    throw 'splash-before-Explorer failed: shell.firstPaint after settle.begin'
}

$outcome = [string]$guest.outcome
if ($outcome -ne 'Complete') {
    throw "Smoke acceptance requires outcome Complete, got '$outcome' (Failed/Reboot is not green)"
}

# jobs.ok / oobe.dismiss / explorer Shell live in Get-WinMintGuestHandoffReadiness (shared with wait).
if ($phases -notcontains 'jobs.workstation.quiet') {
    throw 'FirstLogon quiet chrome missing: phases must contain jobs.workstation.quiet'
}
if ($phases -notcontains 'jobs.wsl.platform.mocked') {
    throw 'hypervisor WSL mock missing: phases must contain jobs.wsl.platform.mocked'
}
if ($phases -notcontains 'shell.chrome') {
    throw 'shell chrome missing: phases must contain shell.chrome'
}

$onlineRemoves = @($phases | Where-Object { $_ -like 'removed.appx.online.*' })
if ($onlineRemoves.Count -gt 0) {
    $deprovisionMarks = @($phases | Where-Object { $_ -like 'deprovisioned.appx.*' })
    if ($deprovisionMarks.Count -eq 0) {
        throw 'AppX safety-net incomplete: removed.appx.online phases present but no deprovisioned.appx.* phase'
    }
}

# DMA hard fields must succeed
# resumeOk + checkpoint.resume proves hard-field re-verify on resume (ticket 17), including setup-region latch.
$dmaOk = ($phases -contains 'settle.ok') -or ($phases -contains 'settle.locationWarn') -or
    (($phases -contains 'settle.resumeOk') -and ($phases -contains 'checkpoint.resume'))
if (-not $dmaOk) {
    throw 'DMA hard fields missing: need settle.ok, settle.locationWarn, or settle.resumeOk+checkpoint.resume'
}

$setupRegionOk = ($phases -contains 'settle.deviceRegionOk') -or ($phases -contains 'settle.deviceRegionRepaired')
if (-not $setupRegionOk) {
    throw 'DMA setup region missing: need settle.deviceRegionOk or settle.deviceRegionRepaired (DeviceRegion Ireland)'
}

# Unlock / handoff: same readiness facts as the wait loop (Get-WinMintGuestHandoffReadiness).
$shellPath = Join-Path $EvidenceDir 'guest\winlogon-shell.txt'
if (-not (Test-Path -LiteralPath $shellPath)) {
    throw "unlock marker missing: expected guest/winlogon-shell.txt (Winlogon Shell after tenure)"
}
$fileShell = ([string](Get-Content -LiteralPath $shellPath -Raw -Encoding utf8)).Trim()
if ([string]::IsNullOrWhiteSpace($fileShell)) {
    throw 'unlock marker empty: guest/winlogon-shell.txt'
}

$handoffShell = if ($StaticEvidenceOnly) { $fileShell } else { $LiveShell.Trim() }
$handoffSupervisor = if ($StaticEvidenceOnly) { $false } else { $SupervisorRunning }
$handoffRunId = if ($StaticEvidenceOnly) { '' } else { $RequiredSmokeRunId }

$handoffReady = Get-WinMintGuestHandoffReadiness -EvidenceDoc $guest `
    -LiveShell $handoffShell -SupervisorRunning:$handoffSupervisor `
    -RequiredSmokeRunId $handoffRunId
if ($handoffReady -cne 'ready') {
    throw ("FirstLogon handoff gate failed " +
        "(readiness=$handoffReady shell='$handoffShell' supervisor=$handoffSupervisor static=$StaticEvidenceOnly)")
}

if ($fileShell -match '(?i)Supervisor\.exe') {
    throw "unlock failed: Winlogon Shell still Supervisor ('$fileShell')"
}
if (-not (Test-WinMintExplorerShellValue $fileShell)) {
    throw "unlock failed: expected explorer.exe in winlogon-shell.txt, got '$fileShell'"
}

$lane = $null
$applyEvidence = Join-Path $EvidenceDir 'apply\evidence.json'
$core = Assert-WinMintImageEvidence `
    -EvidencePath $applyEvidence `
    -ExpectedEvidencePath (Join-Path $EvidenceDir 'apply\expected-evidence.json') `
    -EvidenceLabel 'apply/evidence.json'
$lane = $core.Lane
$digestMap = $core.DigestMap

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
        $removed = "removed.appx.online.$id"
        $marked = @($phaseList | Where-Object { $_ -like "deprovisioned.appx.${id}_*" })
        if ($phaseList -contains $removed -or $marked.Count -gt 0) { continue }
        throw ("online debloat phase missing: expected '$removed' or " +
            "'deprovisioned.appx.${id}_*' (already absent on the image)")
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

$chromePath = Join-Path $EvidenceDir 'guest\shell-chrome.json'
if (-not (Test-Path -LiteralPath $chromePath)) {
    throw 'shell chrome evidence missing: expected guest/shell-chrome.json'
}
$chrome = Get-Content -LiteralPath $chromePath -Raw -Encoding utf8 | ConvertFrom-Json
if ([string]$chrome.schemaVersion -ne 'winmint.shell.chrome/v1') {
    throw "unexpected shell chrome schema '$($chrome.schemaVersion)'"
}
$expectedWallpaper = 'C:\Windows\Web\Wallpaper\Windows\WinMint-Bloom.jpg'
if ([string]$chrome.wallpaperPath -ne $expectedWallpaper) {
    throw "shell chrome wallpaperPath must be $expectedWallpaper, got '$($chrome.wallpaperPath)'"
}
$startPins = @($chrome.startPinIds)
$taskbarPins = @($chrome.taskbarPinIds)
foreach ($id in @('explorer', 'settings', 'terminal')) {
    if ($startPins -cnotcontains $id) {
        throw "shell chrome startPinIds must contain $id"
    }
}
if ($taskbarPins -cnotcontains 'explorer' -or $taskbarPins -cnotcontains 'terminal') {
    throw 'shell chrome taskbarPinIds must contain explorer and terminal'
}

$packageStrict = $false
$applyEvidencePath = Join-Path $EvidenceDir 'apply\evidence.json'
if (Test-Path -LiteralPath $applyEvidencePath -PathType Leaf) {
    $applyDoc = Get-Content -LiteralPath $applyEvidencePath -Raw -Encoding utf8 | ConvertFrom-Json
    if ($applyDoc.PSObject.Properties.Name -contains 'packageStrict') {
        $packageStrict = [bool]$applyDoc.packageStrict
    }
}

$extraPinIds = [ordered]@{
    'Anysphere.Cursor'     = 'cursor'
    'Zen-Team.Zen-Browser' = 'zen-browser'
}
if ($packageStrict) {
    foreach ($pinId in $extraPinIds.Values) {
        if ($startPins -cnotcontains $pinId) {
            throw "package-strict shell chrome startPinIds must contain $pinId"
        }
    }
}
else {
    $nativePath = Join-Path $EvidenceDir 'guest\native-packages.json'
    if (Test-Path -LiteralPath $nativePath -PathType Leaf) {
        $nativePins = Get-Content -LiteralPath $nativePath -Raw -Encoding utf8 | ConvertFrom-Json
        foreach ($pkg in @($nativePins.packages)) {
            $wingetId = [string]$pkg.wingetId
            $pinId = $extraPinIds[$wingetId]
            if ([string]::IsNullOrWhiteSpace($pinId)) { continue }
            if ([string]::IsNullOrWhiteSpace([string]$pkg.binaryPath)) { continue }
            if ($startPins -cnotcontains $pinId) {
                throw "shell chrome startPinIds must contain $pinId (native audit found $wingetId)"
            }
        }
    }
}
if ($null -eq $chrome.quietDwords) {
    throw 'shell chrome quietDwords missing'
}
# Task 6 writes the full ExplorerAdvancedDwords table plus SearchboxTaskbarMode.
# Assert the v1 quiet keys as a subset (must be 0); do not require exact dictionary equality.
$requiredQuiet = [ordered]@{
    SearchboxTaskbarMode = 0
    TaskbarDa            = 0
    TaskbarMn            = 0
    ShowTaskViewButton   = 0
    ShowCopilotButton    = 0
}
foreach ($name in $requiredQuiet.Keys) {
    $prop = $chrome.quietDwords.PSObject.Properties[$name]
    if ($null -eq $prop) {
        throw "shell chrome quietDwords missing $name"
    }
    if ([int]$prop.Value -ne $requiredQuiet[$name]) {
        throw "shell chrome quietDwords.$name must be $($requiredQuiet[$name]), got '$($prop.Value)'"
    }
}

$acceptance = [ordered]@{
    schemaVersion         = 'winmint.smoke.acceptance/v1'
    splashBeforeExplorer  = $true
    outcome               = $outcome
    lane                  = $lane
    liveHandoffVerified   = (-not $StaticEvidenceOnly)
}
$acceptancePath = Join-Path $EvidenceDir 'acceptance.json'
$acceptance | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $acceptancePath -Encoding utf8
Write-Output "Smoke evidence OK → $acceptancePath"
exit 0
