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
    Write-WinMintHostPhase -Lane Apply -Name 'AddQualityUpdates' -Index 9 -Count 14 -Outcome ok -DurationMs 1234
    Write-WinMintHostProgress -Activity Apply -Status 'AddQualityUpdates' -PercentComplete 64
    Write-WinMintHostProgress -Activity Apply -Completed
}
finally {
    $PSStyle.OutputRendering = $old
}

Write-Output 'Test-WinMintHostProgress ok'
