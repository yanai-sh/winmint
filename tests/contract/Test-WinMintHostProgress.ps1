#requires -Version 7.6
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingInvokeExpression',
    '',
    Justification = 'Contract extracts Invoke-WinMintLoggedKernel / Get-WinMintHeartbeatSha256 from source for behavioural checks without elevating Apply.')]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools/host/Write-WinMintHostProgress.ps1')

$helper = Get-Content -LiteralPath (Join-Path $repo 'tools/host/Write-WinMintHostProgress.ps1') -Raw -Encoding utf8
if ($helper -notmatch '\$PSStyle') { throw 'helper must use $PSStyle' }
if ($helper -notmatch "Progress\.View = 'Minimal'") { throw 'helper must set Progress.View to Minimal' }
if ($helper -match 'Spectre') { throw 'helper must not pull a TUI package' }
if ($helper -match 'Clear-Host') { throw 'Format-WinMintHostWatch must return a string; no Clear-Host inside' }
if ($helper -notmatch 'function Write-WinMintHostHeartbeat') { throw 'helper must define Write-WinMintHostHeartbeat' }
if ($helper -notmatch 'function Test-WinMintTrailHeartbeatLine') { throw 'helper must define Test-WinMintTrailHeartbeatLine' }
if ($helper -notmatch 'function Select-WinMintWatchLogTail') { throw 'helper must define Select-WinMintWatchLogTail' }
if ($helper -notmatch 'function Start-WinMintHostWatchProcess') { throw 'helper must spawn watch via Start-WinMintHostWatchProcess' }
if ($helper -notmatch 'wt' -and $helper -notmatch 'WindowsTerminal') { throw 'spawn helper must consider wt.exe' }
if ($helper -notmatch 'UseOSCIndicator') { throw 'helper must set Progress.UseOSCIndicator when interactive VT' }
if (-not (Test-WinMintTrailHeartbeatLine -Line 'AddQualityUpdates running 78s')) { throw 'heartbeat detector missed running line' }
if (Test-WinMintTrailHeartbeatLine -Line 'Catalog BITS start KB1') { throw 'heartbeat detector false positive' }
$filtered = @(Select-WinMintWatchLogTail -Lines @(
        'Catalog BITS start KB1',
        'AddQualityUpdates running 20s',
        'AddQualityUpdates running 40s',
        'quality hash ok leaf.msu'
    ) -Count 8)
if ($filtered -contains 'AddQualityUpdates running 20s') { throw 'Select-WinMintWatchLogTail must drop heartbeats' }
if ($filtered.Count -ne 2) { throw 'Select-WinMintWatchLogTail kept wrong rows' }

$plan = Get-Content -LiteralPath (Join-Path $repo 'servicing/Invoke-ServicingPlan.ps1') -Raw -Encoding utf8
if ($plan -notmatch 'Write-WinMintHostPhase') { throw 'elevated loop must print host phases' }
if ($plan -notmatch 'Write-WinMintHostProgress') { throw 'elevated loop must drive Write-Progress' }
if ($plan -notmatch 'function Invoke-WinMintLoggedKernel') { throw 'elevated loop must log kernels through Invoke-WinMintLoggedKernel' }
if ($plan -notmatch 'Write-WinMintHostHeartbeat') { throw 'logged kernel must call Write-WinMintHostHeartbeat' }
$kernelFn = [regex]::Match($plan, '(?ms)^function Invoke-WinMintLoggedKernel \{.*?^\}').Value
if ($kernelFn -notmatch 'Write-WinMintHostHeartbeat -Opcode') { throw 'heartbeat helper not called with -Opcode' }
if ($kernelFn -match '\$text = "\$Opcode running[\s\S]{0,80}Write-Host \$text') {
    throw 'heartbeat still Write-Host'
}
Invoke-Expression $kernelFn
$kernelProbe = Join-Path ([IO.Path]::GetTempPath()) 'winmint-logged-kernel.ps1'
$kernelLog = Join-Path ([IO.Path]::GetTempPath()) 'winmint-logged-kernel.log'
Set-Content -LiteralPath $kernelProbe -Encoding utf8 -Value "Write-Output 'kernel-line'`r`nWrite-Host 'kernel-host'`r`nStart-Sleep -Seconds 4`r`n"
Invoke-WinMintLoggedKernel -Path $kernelProbe -Parameters @{} -LogFile $kernelLog -Opcode 'ProbeOp' -QuietSeconds 1
$kernelText = Get-Content -LiteralPath $kernelLog -Raw -Encoding utf8
Remove-Item -LiteralPath $kernelProbe, $kernelLog -Force
if ($kernelText -notmatch 'kernel-line') { throw 'logged kernel dropped stdout' }
if ($kernelText -notmatch 'kernel-host') { throw 'logged kernel dropped host line' }
if ($kernelText -notmatch 'ProbeOp running') { throw 'silent kernel produced no heartbeat' }
if ($plan -notmatch "updated=.*`r?`n.*stage=.*`r?`n.*log=") { throw 'apply-status schema keys changed' }
if ($plan -match "Resolve-KernelScript.*Write-WinMintHostProgress") { throw 'helper must not be an opcode kernel' }

$quality = Get-Content -LiteralPath (Join-Path $repo 'servicing/Add-QualityUpdates.ps1') -Raw -Encoding utf8
if ($quality -notmatch 'quality package-set start') { throw 'AddQualityUpdates must announce package-set discovery' }
if ($quality -notmatch 'Catalog BITS start') { throw 'AddQualityUpdates must announce BITS' }
if ($quality -notmatch 'quality hash start') { throw 'AddQualityUpdates must announce hash' }
if ($quality -notmatch 'quality expand start') { throw 'AddQualityUpdates must announce expand' }
if ($quality -notmatch 'quality packages apply') { throw 'AddQualityUpdates must announce package apply' }
Invoke-Expression ([regex]::Match($quality, '(?ms)^function Get-WinMintHeartbeatSha256 \{.*?^\}').Value)
$hashSample = Join-Path ([IO.Path]::GetTempPath()) 'winmint-heartbeat-sha256.txt'
Set-Content -LiteralPath $hashSample -Value 'winmint-heartbeat' -Encoding ascii -NoNewline
$heartbeat = @(Get-WinMintHeartbeatSha256 -Path $hashSample) | Select-Object -Last 1
$expectedSha = (Get-FileHash -LiteralPath $hashSample -Algorithm SHA256).Hash.ToLowerInvariant()
Remove-Item -LiteralPath $hashSample -Force
if ($heartbeat -ne $expectedSha) { throw "heartbeat sha256 $heartbeat != $expectedSha" }
$searchAt = $quality.IndexOf('quality package-set start')
$resolvedAt = $quality.IndexOf('$set = Get-WinMintQualityPackageSet')
$bitsAt = $quality.IndexOf('Catalog BITS start')
$lcuAt = $quality.IndexOf('$lcuPath = Get-WinMintCatalogPayload')
if (-not ($searchAt -ge 0 -and $searchAt -lt $resolvedAt)) { throw 'quality package-set start must not live inside the $set assignment' }
if (-not ($bitsAt -ge 0 -and $bitsAt -lt $lcuAt)) { throw 'Catalog BITS start must not live inside the $lcuPath assignment' }
foreach ($fn in [regex]::Matches($quality, '(?ms)^function\s+\S+.*?^}')) {
    if ($fn.Value -match 'quality package-set start') { throw 'quality package-set start must not live inside a function' }
    if ($fn.Value -match 'Catalog BITS start') { throw 'Catalog BITS start must not live inside a function' }
}

$smoke = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Invoke-Smoke.ps1') -Raw -Encoding utf8
if ($smoke -notmatch 'Write-WinMintHostPhase') { throw 'Smoke host lines must use helper phase' }
if ($smoke -notmatch 'wait \$\{elapsedMin\}m') { throw 'Smoke wait must print a beat every poll' }
if ($smoke -notmatch 'packages\.evidence\.json') { throw 'Smoke must pull packages.evidence.json when the guest wrote it' }
if ($smoke -match 'Start-Sleep -Seconds 30') { throw 'Smoke wait poll must stay at 20s so the beat is visible' }
if ($smoke -notmatch 'Write-WinMintHostProgress') { throw 'Smoke host lines must use helper progress' }
if ($smoke -notmatch 'Write-WinMintHostProgress -Activity wait -Status') { throw 'wait phase uses helper without percent' }
if ($smoke -match 'PercentComplete') { throw 'Smoke wait must not invent a fake percent' }
if ($smoke -notmatch 'Start-WinMintHostWatchProcess') { throw 'Invoke-Smoke must use Start-WinMintHostWatchProcess' }
$spawnAt = $smoke.IndexOf('Start-WinMintHostWatchProcess')
if ($spawnAt -lt 0) { throw 'Invoke-Smoke must spawn watch via Start-WinMintHostWatchProcess' }
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
if ($watchHost -notmatch 'MarkerPath') { throw 'Watch-Host must accept -MarkerPath and self-stamp PID' }
if ($watchHost -notmatch 'Select-WinMintWatchLogTail') { throw 'Watch-Host must filter log tail via Select-WinMintWatchLogTail' }
if ($watchHost -notmatch '-Tail 40') { throw 'Watch-Host must read a deep raw tail before filtering' }

$just = Get-Content -LiteralPath (Join-Path $repo 'Justfile') -Raw -Encoding utf8
if ($just -notmatch 'Watch-Host.ps1') { throw 'just watch-* must call Watch-Host' }
if ($just -notmatch "-Kind apply") { throw 'just watch-apply must pass -Kind apply' }
if ($just -match 'Get-Content -LiteralPath.*apply-status') { throw 'just watch-apply must not Get-Content -Wait the apply-status file' }

$old = $PSStyle.OutputRendering
try {
    $PSStyle.OutputRendering = 'PlainText'
    $dashNoise = Format-WinMintHostWatch -Title 'watch' -Verdict 'awaiting-run' -Phase 'apply' `
        -ApplyStage 'AddQualityUpdates' -LogLeaf '10-AddQualityUpdates.log' `
        -LogTail (Select-WinMintWatchLogTail -Lines @(
            'Catalog BITS start KB1',
            'AddQualityUpdates running 78s',
            'AddQualityUpdates running 98s',
            'quality hash ok x.msu'
        ) -Count 8)
    if ($dashNoise -match 'running \d+s') { throw 'watch format must not show heartbeat tail' }
    if ($dashNoise -notmatch 'Catalog BITS start') { throw 'watch format dropped meaningful tail' }

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
