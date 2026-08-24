#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools/host/Write-WinMintHostProgress.ps1')

$helper = Get-Content -LiteralPath (Join-Path $repo 'tools/host/Write-WinMintHostProgress.ps1') -Raw -Encoding utf8
if ($helper -notmatch '\$PSStyle') { throw 'helper must use $PSStyle' }
if ($helper -notmatch "Progress\.View = 'Minimal'") { throw 'helper must set Progress.View to Minimal' }
if ($helper -match 'Spectre') { throw 'helper must not pull a TUI package' }
if ($helper -match 'Clear-Host') { throw 'Format-WinMintHostWatch must return a string; no Clear-Host inside' }

$plan = Get-Content -LiteralPath (Join-Path $repo 'servicing/Invoke-ServicingPlan.ps1') -Raw -Encoding utf8
if ($plan -notmatch 'Write-WinMintHostPhase') { throw 'elevated loop must print host phases' }
if ($plan -notmatch 'Write-WinMintHostProgress') { throw 'elevated loop must drive Write-Progress' }
if ($plan -notmatch 'Tee-Object') { throw 'elevated loop must keep Tee-Object' }
if ($plan -notmatch "updated=.*`r?`n.*stage=.*`r?`n.*log=") { throw 'apply-status schema keys changed' }
if ($plan -match "Resolve-KernelScript.*Write-WinMintHostProgress") { throw 'helper must not be an opcode kernel' }

$quality = Get-Content -LiteralPath (Join-Path $repo 'servicing/Add-QualityUpdates.ps1') -Raw -Encoding utf8
if ($quality -notmatch 'Catalog search start') { throw 'AddQualityUpdates must announce Catalog search' }
if ($quality -notmatch 'Catalog BITS start') { throw 'AddQualityUpdates must announce BITS' }
$searchAt = $quality.IndexOf('Catalog search start')
$resolvedAt = $quality.IndexOf('$resolved = Invoke-WinMintQualityCatalogResolve')
$bitsAt = $quality.IndexOf('Catalog BITS start')
$lcuAt = $quality.IndexOf('$lcuPath = Get-WinMintCatalogPayload')
if (-not ($searchAt -ge 0 -and $searchAt -lt $resolvedAt)) { throw 'Catalog search start must not live inside the $resolved assignment' }
if (-not ($bitsAt -ge 0 -and $bitsAt -lt $lcuAt)) { throw 'Catalog BITS start must not live inside the $lcuPath assignment' }
foreach ($fn in [regex]::Matches($quality, '(?ms)^function\s+\S+.*?^}')) {
    if ($fn.Value -match 'Catalog search start') { throw 'Catalog search start must not live inside a function' }
    if ($fn.Value -match 'Catalog BITS start') { throw 'Catalog BITS start must not live inside a function' }
}

$smoke = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Invoke-Smoke.ps1') -Raw -Encoding utf8
if ($smoke -notmatch 'Write-WinMintHostPhase') { throw 'Smoke host lines must use helper phase' }
if ($smoke -notmatch 'Write-WinMintHostProgress') { throw 'Smoke host lines must use helper progress' }
if ($smoke -notmatch 'Write-WinMintHostProgress -Activity wait -Status') { throw 'wait phase uses helper without percent' }
if ($smoke -match 'PercentComplete') { throw 'Smoke wait must not invent a fake percent' }
$spawnAt = $smoke.IndexOf('Watch-Host.ps1')
if ($spawnAt -lt 0) { throw 'Invoke-Smoke must spawn Watch-Host' }
$spawn = $smoke.Substring($spawnAt, [Math]::Min(400, $smoke.Length - $spawnAt))
if ($spawn -notmatch 'PriorRunId') { throw 'spawned watcher must receive leftover or empty PriorRunId' }
if ($spawn -match '\$runId') { throw 'spawned watcher must not receive this run''s already-written runId as PriorRunId' }
$suspendWarnAt = $smoke.IndexOf('Could not capture/suspend VM after failure')
if ($suspendWarnAt -lt 0) { throw 'Smoke fail missing suspend-try warning' }
$completedAfterFailTry = $false
foreach ($m in [regex]::Matches($smoke, 'Write-WinMintHostProgress -Activity Smoke -Completed')) {
    if ($m.Index -gt $suspendWarnAt) { $completedAfterFailTry = $true }
}
if (-not $completedAfterFailTry) { throw 'Smoke fail must Completed after suspend try (including skip)' }

$watchHost = Get-Content -LiteralPath (Join-Path $repo 'tools/host/Watch-Host.ps1') -Raw -Encoding utf8
if ($watchHost -notmatch 'Read-WinMintApplyStatus') { throw 'Watch-Host smoke/apply must read apply-status via Read-WinMintApplyStatus' }
if ($watchHost -match 'Get-Date') { throw 'Watch-Host must not pass Get-Date as a dashboard clock' }
if ($watchHost -notmatch "-ne 'apply'") { throw 'Watch-Host apply kind must not exit on done' }
if ($watchHost -notmatch 'Format-WinMintHostWatch') { throw 'Watch-Host must render via Format-WinMintHostWatch' }

$just = Get-Content -LiteralPath (Join-Path $repo 'Justfile') -Raw -Encoding utf8
if ($just -notmatch 'Watch-Host.ps1') { throw 'just watch-* must call Watch-Host' }
if ($just -notmatch "-Kind apply") { throw 'just watch-apply must pass -Kind apply' }
if ($just -match 'Get-Content -LiteralPath.*apply-status') { throw 'just watch-apply must not Get-Content -Wait the apply-status file' }

$old = $PSStyle.OutputRendering
try {
    $PSStyle.OutputRendering = 'PlainText'
    $dash = Format-WinMintHostWatch -Title 'watch' -Clock '12:00:00' -Verdict 'done' `
        -Phase 'green' -VmState 'Running' -Heartbeat 'OK' -StallMinutesLeft 12 `
        -WallMinutesLeft 40 -ApplyStage 'done' -LastHostLine 'Smoke green' `
        -LogLeaf '09-AddQualityUpdates.log' -LogTail @('Catalog search start', 'AddQualityUpdates ok')
    if ($dash -isnot [string]) { throw 'Format-WinMintHostWatch must return a string' }
    if ($dash -notmatch 'verdict') { throw 'dashboard missing verdict' }
    if ($dash -notmatch 'green') { throw 'dashboard missing phase' }
    if ($dash -notmatch '12m') { throw 'dashboard recomputed stall instead of displaying file value' }
    if ($dash -notmatch '40m') { throw 'dashboard missing wall from file' }
    if ($dash -notmatch 'Smoke green') { throw 'dashboard missing last host line' }
    if ($dash -notmatch '09-AddQualityUpdates.log') { throw 'dashboard missing log leaf' }
    if ((@($dash -split "`n" | Where-Object { $_ -match 'Catalog search start' }).Count -ne 1)) { throw 'log tail not shown' }

    $checkDash = Format-WinMintHostWatch -Title 'check' -Verdict 'continue' -Phase 'test' -Leaf '' -LastHostLine 'dotnet test'
    if ($checkDash -match 'stall') { throw 'check layout must omit stall/wall' }
    if ($checkDash -match 'heartbeat') { throw 'check layout must omit VM/heartbeat' }
    if ($checkDash -notmatch 'test') { throw 'check layout missing phase' }
    if ($checkDash -match '12:00:00') { throw 'check layout must omit clock unless passed' }

    $applyTmp = Join-Path ([IO.Path]::GetTempPath()) ('apply-status-' + [guid]::NewGuid().ToString('N') + '.txt')
    Set-Content -LiteralPath $applyTmp -Value "updated=2026-01-01T00:00:00Z`nstage=AddQualityUpdates`nlog=C:\logs\09.log" -Encoding utf8
    $snap = Read-WinMintApplyStatus -Path $applyTmp
    if ($snap.Stage -cne 'AddQualityUpdates') { throw 'Read-WinMintApplyStatus missed stage' }
    if ($snap.Log -cne 'C:\logs\09.log') { throw 'Read-WinMintApplyStatus missed log' }
    Remove-Item -LiteralPath $applyTmp -Force

    Write-WinMintHostPhase -Lane Apply -Name 'AddQualityUpdates' -Index 9 -Count 14 -Outcome ok -DurationMs 1234
    Write-WinMintHostProgress -Activity Apply -Status 'AddQualityUpdates' -PercentComplete 64
    Write-WinMintHostProgress -Activity Apply -Completed
}
finally {
    $PSStyle.OutputRendering = $old
}

Write-Output 'Test-WinMintHostProgress ok'
