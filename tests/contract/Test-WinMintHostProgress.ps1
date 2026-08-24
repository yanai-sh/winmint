#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools/host/Write-WinMintHostProgress.ps1')

function Assert-True($Value, [string] $Message) {
    if (-not $Value) { throw $Message }
}

$helper = Get-Content -LiteralPath (Join-Path $repo 'tools/host/Write-WinMintHostProgress.ps1') -Raw -Encoding utf8
Assert-True ($helper -match '\$PSStyle') 'helper must use $PSStyle'
Assert-True ($helper -match "Progress\.View = 'Minimal'") 'helper must set Progress.View to Minimal'
Assert-True ($helper -notmatch 'Spectre') 'helper must not pull a TUI package'
Assert-True ($helper -notmatch 'Clear-Host') 'Format-WinMintHostWatch must return a string; no Clear-Host inside'

$plan = Get-Content -LiteralPath (Join-Path $repo 'servicing/Invoke-ServicingPlan.ps1') -Raw -Encoding utf8
Assert-True ($plan -match 'Write-WinMintHostPhase') 'elevated loop must print host phases'
Assert-True ($plan -match 'Write-WinMintHostProgress') 'elevated loop must drive Write-Progress'
Assert-True ($plan -match 'Tee-Object') 'elevated loop must keep Tee-Object'
Assert-True ($plan -match "updated=.*`r?`n.*stage=.*`r?`n.*log=") 'apply-status schema keys changed'
Assert-True ($plan -notmatch "Resolve-KernelScript.*Write-WinMintHostProgress") 'helper must not be an opcode kernel'

$quality = Get-Content -LiteralPath (Join-Path $repo 'servicing/Add-QualityUpdates.ps1') -Raw -Encoding utf8
Assert-True ($quality -match 'Catalog search start') 'AddQualityUpdates must announce Catalog search'
Assert-True ($quality -match 'Catalog BITS start') 'AddQualityUpdates must announce BITS'
$searchAt = $quality.IndexOf('Catalog search start')
$resolvedAt = $quality.IndexOf('$resolved = Invoke-WinMintQualityCatalogResolve')
$bitsAt = $quality.IndexOf('Catalog BITS start')
$lcuAt = $quality.IndexOf('$lcuPath = Get-WinMintCatalogPayload')
Assert-True ($searchAt -ge 0 -and $searchAt -lt $resolvedAt) 'Catalog search start must not live inside the $resolved assignment'
Assert-True ($bitsAt -ge 0 -and $bitsAt -lt $lcuAt) 'Catalog BITS start must not live inside the $lcuPath assignment'
foreach ($fn in [regex]::Matches($quality, '(?ms)^function\s+\S+.*?^}')) {
    Assert-True ($fn.Value -notmatch 'Catalog search start') 'Catalog search start must not live inside a function'
    Assert-True ($fn.Value -notmatch 'Catalog BITS start') 'Catalog BITS start must not live inside a function'
}

$smoke = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Invoke-Smoke.ps1') -Raw -Encoding utf8
Assert-True ($smoke -match 'Write-WinMintHostPhase') 'Smoke host lines must use helper phase'
Assert-True ($smoke -match 'Write-WinMintHostProgress') 'Smoke host lines must use helper progress'
Assert-True ($smoke -match 'Write-WinMintHostProgress -Activity wait -Status') 'wait phase uses helper without percent'
Assert-True ($smoke -notmatch 'PercentComplete') 'Smoke wait must not invent a fake percent'
$spawnAt = $smoke.IndexOf('Watch-SmokeHost.ps1')
Assert-True ($spawnAt -ge 0) 'Invoke-Smoke must spawn Watch-SmokeHost'
$spawn = $smoke.Substring($spawnAt, [Math]::Min(400, $smoke.Length - $spawnAt))
Assert-True ($spawn -match 'PriorRunId') 'spawned watcher must receive leftover or empty PriorRunId'
Assert-True ($spawn -notmatch '\$runId') 'spawned watcher must not receive this run''s already-written runId as PriorRunId'
$suspendWarnAt = $smoke.IndexOf('Could not capture/suspend VM after failure')
Assert-True ($suspendWarnAt -ge 0) 'Smoke fail missing suspend-try warning'
$completedAfterFailTry = $false
foreach ($m in [regex]::Matches($smoke, 'Write-WinMintHostProgress -Activity Smoke -Completed')) {
    if ($m.Index -gt $suspendWarnAt) { $completedAfterFailTry = $true }
}
Assert-True $completedAfterFailTry 'Smoke fail must Completed after suspend try (including skip)'

$watchHost = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Watch-SmokeHost.ps1') -Raw -Encoding utf8
Assert-True ($watchHost -match 'Read-WinMintApplyStatus') 'Watch-SmokeHost must read apply-status via Read-WinMintApplyStatus'
Assert-True ($watchHost -notmatch 'Get-Date') 'Watch-SmokeHost must not pass Get-Date as a dashboard clock'

$applyWatch = Get-Content -LiteralPath (Join-Path $repo 'tools/host/Watch-ApplyHost.ps1') -Raw -Encoding utf8
Assert-True ($applyWatch -match 'Read-WinMintApplyStatus') 'Watch-ApplyHost must use Read-WinMintApplyStatus'
Assert-True ($applyWatch -match 'Format-WinMintHostWatch') 'Watch-ApplyHost must render via Format-WinMintHostWatch'

$just = Get-Content -LiteralPath (Join-Path $repo 'Justfile') -Raw -Encoding utf8
Assert-True ($just -match 'Watch-ApplyHost.ps1') 'just watch-apply must call Watch-ApplyHost'
Assert-True ($just -notmatch 'Get-Content -LiteralPath.*apply-status') 'just watch-apply must not Get-Content -Wait the apply-status file'

$old = $PSStyle.OutputRendering
try {
    $PSStyle.OutputRendering = 'PlainText'
    $dash = Format-WinMintHostWatch -Title 'watch' -Clock '12:00:00' -Verdict 'done' `
        -Phase 'green' -VmState 'Running' -Heartbeat 'OK' -StallMinutesLeft 12 `
        -WallMinutesLeft 40 -ApplyStage 'done' -LastHostLine 'Smoke green' `
        -LogLeaf '09-AddQualityUpdates.log' -LogTail @('Catalog search start', 'AddQualityUpdates ok')
    Assert-True ($dash -is [string]) 'Format-WinMintHostWatch must return a string'
    Assert-True ($dash -match 'verdict') 'dashboard missing verdict'
    Assert-True ($dash -match 'green') 'dashboard missing phase'
    Assert-True ($dash -match '12m') 'dashboard recomputed stall instead of displaying file value'
    Assert-True ($dash -match '40m') 'dashboard missing wall from file'
    Assert-True ($dash -match 'Smoke green') 'dashboard missing last host line'
    Assert-True ($dash -match '09-AddQualityUpdates.log') 'dashboard missing log leaf'
    Assert-True ((@($dash -split "`n" | Where-Object { $_ -match 'Catalog search start' }).Count -eq 1)) 'log tail not shown'

    $checkDash = Format-WinMintHostWatch -Title 'check' -Verdict 'continue' -Phase 'test' -Leaf '' -LastHostLine 'dotnet test'
    Assert-True ($checkDash -notmatch 'stall') 'check layout must omit stall/wall'
    Assert-True ($checkDash -notmatch 'heartbeat') 'check layout must omit VM/heartbeat'
    Assert-True ($checkDash -match 'test') 'check layout missing phase'
    Assert-True ($checkDash -notmatch '12:00:00') 'check layout must omit clock unless passed'

    $applyTmp = Join-Path ([IO.Path]::GetTempPath()) ('apply-status-' + [guid]::NewGuid().ToString('N') + '.txt')
    Set-Content -LiteralPath $applyTmp -Value "updated=2026-01-01T00:00:00Z`nstage=AddQualityUpdates`nlog=C:\logs\09.log" -Encoding utf8
    $snap = Read-WinMintApplyStatus -Path $applyTmp
    Assert-True ($snap.Stage -eq 'AddQualityUpdates') 'Read-WinMintApplyStatus missed stage'
    Assert-True ($snap.Log -eq 'C:\logs\09.log') 'Read-WinMintApplyStatus missed log'
    Remove-Item -LiteralPath $applyTmp -Force

    Write-WinMintHostPhase -Lane Apply -Name 'AddQualityUpdates' -Index 9 -Count 14 -Outcome ok -DurationMs 1234
    Write-WinMintHostProgress -Activity Apply -Status 'AddQualityUpdates' -PercentComplete 64
    Write-WinMintHostProgress -Activity Apply -Completed
}
finally {
    $PSStyle.OutputRendering = $old
}

Write-Output 'Test-WinMintHostProgress ok'
