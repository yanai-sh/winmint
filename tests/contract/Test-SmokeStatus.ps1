#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools/vm/SmokeStatus.ps1')
. (Join-Path $repo 'tools/host/Write-WinMintHostProgress.ps1')

$smoke = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Invoke-Smoke.ps1') -Raw -Encoding utf8
if ($smoke -notmatch 'tools[/\\]vm[/\\]SmokeStatus\.ps1') { throw 'Invoke-Smoke must dot-source SmokeStatus.ps1' }
if ($smoke -notmatch 'Get-WinMintApplyHostFailure') { throw 'Apply wait must use Get-WinMintApplyHostFailure' }
if ($smoke -notmatch "Resolve-SmokePhase -HostStage failed") { throw 'Apply/wait failures must write phase=failed' }
if ($smoke -match 'Get-Content[^\n]*smoke-status\.json') { throw 'must not read smoke-status.json as control plane' }
if ($smoke -notmatch 'Get-SmokeWaitTick') { throw 'Invoke-Smoke wait loop must call Get-SmokeWaitTick' }
$statusSrc = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/SmokeStatus.ps1') -Raw -Encoding utf8
if ($statusSrc -notmatch 'EMPTY_VHD:') { throw 'empty-VHD throw prefix missing (operator copy)' }
if ($smoke -notmatch '\[Diagnostics\.Stopwatch\]') { throw 'stall/wall/empty-vhd must use Stopwatch, not UtcNow deadlines' }
if ($smoke -notmatch 'Select-WinMintGuestEvidencePath') { throw 'guest evidence must select by outcome, not LastWriteTime' }
if ($smoke -notmatch 'Test-WinMintGuestEvidenceTerminal') {
    throw 'Invoke-Smoke must fail-close Complete evidence with Test-WinMintGuestEvidenceTerminal'
}
if ($smoke -match 'process-exited-early' -or $smoke -match 'Find-SmokePids') {
    throw 'Invoke-Smoke must not infer harness death from process lists'
}
if ($smoke -notmatch "Remove-Item[^\n]*priorProjections" -or $smoke -notmatch "'evidence\.json', 'stages\.json'") {
    throw 'Invoke-Smoke must clear prior-run Apply projections (apply-status/failure/evidence/stages/expected) before Apply'
}
if ($smoke -notmatch 'if \(\$SkipApply\) \{ Resolve-WinMintOutputIso') {
    throw 'Full runs must not resolve the Output ISO before Apply (stale winmint_*.iso would fail-close a fresh Apply)'
}
if ($smoke.IndexOf('Write-SmokeStatus') -gt $smoke.IndexOf('Watch-Host.ps1')) {
    throw 'Invoke-Smoke must write this run''s status before spawning Watch-Host (stale-status guard)'
}
if ($smoke -notmatch 'Resolve-WinMintSmokeGuestCredential') {
    throw 'Invoke-Smoke must resolve guest credentials via Resolve-WinMintSmokeGuestCredential'
}
if ($smoke -notmatch 'ExpectNativePackageAudit:\$expectNativePackageAudit') {
    throw 'assert splat must bind -ExpectNativePackageAudit as a switch, not a positional string'
}
if ($smoke -notmatch 'Save-SmokeVmScreenshot') {
    throw 'Invoke-Smoke must capture a VM console screenshot on failure/half-stall'
}
if ($smoke -notmatch 'Get-SmokeSuspendVmDecision') {
    throw 'Invoke-Smoke must Suspend-VM on stall/wall/reboot-loop via Get-SmokeSuspendVmDecision'
}
if ($smoke -notmatch 'Stop-SmokeVmGuest') {
    throw 'Invoke-Smoke must ACPI-stop leftover/assert-fail VMs (TurnOff is DirtyShutdown)'
}
if ($smoke -notmatch "failVmAction -eq 'shutdown'") {
    throw 'assert/guest fail must ACPI-stop when Get-SmokeSuspendVmDecision returns shutdown'
}
if ($smoke -notmatch 'PrimaryOperationalStatus') {
    throw 'Heartbeat must use PrimaryOperationalStatus, not a localized OK string'
}
if ($smoke -notmatch 'ExplorerRunning') {
    throw 'Live handoff probe must check explorer.exe is running'
}
if ($smoke -notmatch 'LastProbeError') {
    throw 'Invoke-Smoke must surface the last PS Direct probe error'
}
if ($smoke -notmatch 'ProfilePath') {
    throw 'Invoke-Smoke must take -ProfilePath (not the automatic \$PROFILE)'
}
if ($smoke -notmatch '-NonInteractive') {
    throw 'Watcher spawn must pass -NonInteractive so prompts fail closed'
}
if ($smoke -notmatch 'Get-SmokeWatcherSpawnDecision') {
    throw 'Invoke-Smoke must skip a live watcher via Get-SmokeWatcherSpawnDecision'
}
if ($smoke -notmatch '(?s)LastProbeError = \[string\]\$_\.Exception\.Message\s+\$script:LastSupervisorRunning = \$false') {
    throw 'probe-fail must not keep Supervisor-alive'
}

$justfile = Get-Content -LiteralPath (Join-Path $repo 'Justfile') -Raw -Encoding utf8
if ($justfile -notmatch 'NonInteractive') {
    throw 'just smoke / smoke-assert must pass -NonInteractive'
}
if ($justfile -notmatch 'STALL=') {
    throw 'just smoke must expose STALL'
}
if ($justfile -notmatch 'MONITOR="0" STALL="45"') {
    throw 'just smoke must default MONITOR=0 (PowerShell treats empty string as truthy in recipe bodies)'
}
if ($justfile -match '(?ms)^smoke-maintainer[^\n]*:\s*\r?\n\s+just smoke ') {
    throw 'smoke-maintainer must not nest `just smoke` (Windows positional forwarding breaks WALL/MONITOR)'
}
if ($justfile -notmatch 'Invoke-SmokeRecipe\.ps1') {
    throw 'just smoke recipes must call tools/vm/Invoke-SmokeRecipe.ps1'
}
$recipe = Get-Content -LiteralPath (Join-Path $repo 'tools\vm\Invoke-SmokeRecipe.ps1') -Raw -Encoding utf8
if ($recipe -notmatch 'Invoke-Smoke\.ps1') { throw 'Invoke-SmokeRecipe must delegate to Invoke-Smoke.ps1' }
if ($recipe -notmatch 'Maintainer') { throw 'Invoke-SmokeRecipe must support -Maintainer' }

$watch = Get-Content -LiteralPath (Join-Path $repo 'tools/host/Watch-Host.ps1') -Raw -Encoding utf8
if ($watch -notmatch 'Get-SmokeWatchVerdict') { throw 'Watch-Host smoke must call Get-SmokeWatchVerdict' }
if ($watch -notmatch 'PriorRunId') { throw 'Watch-Host smoke must pass -PriorRunId' }
if ($watch -notmatch 'Format-WinMintHostWatch') { throw 'Watch-Host must render via Format-WinMintHostWatch' }
if ($watch -match 'Get-Date') { throw 'Watch-Host must not use Get-Date as a dashboard clock' }
if ($watch -notmatch '\[Diagnostics\.Stopwatch\]') { throw 'Watch-Host smoke age must use Stopwatch' }
if ($watch -notmatch 'PSBoundParameters' -or $watch -notmatch 'ContainsKey') {
    throw 'Watch-Host must not treat the post-stamp file as PriorRunId when the parent bound leftover/empty'
}
$spawnAt = $smoke.IndexOf('Watch-Host.ps1')
if ($spawnAt -lt 0) { throw 'Invoke-Smoke must spawn Watch-Host' }
$spawn = $smoke.Substring($spawnAt, [Math]::Min(400, $smoke.Length - $spawnAt))
if ($spawn -notmatch 'PriorRunId') {
    throw 'spawned watcher must receive leftover or empty -PriorRunId (parent already stamped)'
}
if ($spawn -match '\$runId') {
    throw 'spawned watcher must not receive this run''s already-written runId as PriorRunId'
}

function Invoke-Tick {
    param([hashtable] $Over = @{})
    $s = @{
        VmState                  = 'Running'
        LastVmState              = 'Running'
        Cpu                      = 0
        VhdFileSizeBytes         = 2GB
        VhdHasImage              = $true
        HeartbeatOk              = $false
        GuestUpSticky            = $false
        ConsecutiveHeartbeatOk   = 0
        DiskBootPreferred        = $false
        DvdEjected               = $false
        SmokeRunIdStamped        = $false
        LastFingerprint          = ''
        Fingerprint              = ''
        SupervisorRunning        = $false
        SetupRebootCount         = 0
        MaxSetupReboots          = 8
        StallElapsedMinutes      = 0
        StallMinutes             = 45
        EmptyVhdRunningSeconds   = 0
        EmptyVhdFailAfterSeconds = 480
        NudgeElapsedMinutes      = 0
        HalfStallShot            = $false
    }
    foreach ($k in $Over.Keys) { $s[$k] = $Over[$k] }
    Get-SmokeWaitTick -Snap ([pscustomobject]$s)
}

if ((Resolve-SmokePhase -HostStage apply) -cne 'apply') { throw 'apply stage' }
if ((Resolve-SmokePhase -HostStage assert) -cne 'assert') { throw 'assert stage' }
if ((Resolve-SmokePhase -HostStage green) -cne 'green') { throw 'green stage' }
if ((Resolve-SmokePhase -HostStage failed) -cne 'failed') { throw 'failed stage' }
if ((Resolve-SmokePhase -HostStage wait -VmState Stopping) -cne 'setup-reboot') { throw 'setup reboot' }
if ((Resolve-SmokePhase -HostStage wait -VmState Running -VhdFileSizeBytes 100MB) -cne 'vm-boot') { throw 'empty VHD' }
if ((Resolve-SmokePhase -HostStage wait -VmState Running -VhdFileSizeBytes 1GB) -cne 'winpe-apply') { throw 'VHD has image' }
if ((Resolve-SmokePhase -HostStage wait -VmState Running -VhdFileSizeBytes 1GB -HeartbeatOk) -cne 'guest-up') { throw 'heartbeat wins VHD' }

$t = Invoke-Tick @{ HeartbeatOk = $true; ConsecutiveHeartbeatOk = 0 }
if ($t.Phase -cne 'guest-up') { throw 'first HB still guest-up' }
if ([bool]$t.GuestUpSticky) { throw 'sticky arms at 2' }
$t = Invoke-Tick @{ HeartbeatOk = $true; ConsecutiveHeartbeatOk = 1 }
if (-not [bool]$t.GuestUpSticky) { throw 'sticky armed' }
$t = Invoke-Tick @{ HeartbeatOk = $false; GuestUpSticky = $true; ConsecutiveHeartbeatOk = 2 }
if ($t.Phase -cne 'guest-up') { throw 'sticky survives HB blip' }
$t = Invoke-Tick @{ VmState = 'Off'; HeartbeatOk = $false; GuestUpSticky = $true; ConsecutiveHeartbeatOk = 2 }
if ($t.Phase -cne 'setup-reboot') { throw 'Off clears sticky path' }
if ([bool]$t.GuestUpSticky) { throw 'Off clears sticky flag' }

$t = Invoke-Tick @{ SmokeRunIdStamped = $true; HeartbeatOk = $true }
if ([bool]$t.TryStamp) { throw 'already stamped' }
$t = Invoke-Tick @{ SmokeRunIdStamped = $false; HeartbeatOk = $false }
if ([bool]$t.TryStamp) { throw 'no heartbeat yet' }
$t = Invoke-Tick @{ SmokeRunIdStamped = $false; HeartbeatOk = $true }
if (-not [bool]$t.TryStamp) { throw 'first contact' }

$t = Invoke-Tick @{ VmState = 'Starting'; Cpu = 0 }
if (-not [bool]$t.ExtendStall) { throw 'reboot churn extends' }
$t = Invoke-Tick @{ Cpu = 40; GuestUpSticky = $false }
if (-not [bool]$t.ExtendStall) { throw 'pre-guest-up CPU extends' }
$t = Invoke-Tick @{ Cpu = 90; GuestUpSticky = $true; SupervisorRunning = $false; Fingerprint = '1:Reboot'; LastFingerprint = '1:Reboot' }
if ([bool]$t.ExtendStall) { throw 'CEH spinner after guest-up does not extend' }
$t = Invoke-Tick @{ Cpu = 0; GuestUpSticky = $true; Fingerprint = '2:Complete'; LastFingerprint = '1:Reboot' }
if (-not [bool]$t.ExtendStall) { throw 'new evidence extends after guest-up' }
$t = Invoke-Tick @{ GuestUpSticky = $true; SupervisorRunning = $true }
if (-not [bool]$t.ExtendStall) { throw 'Supervisor alive extends after guest-up' }

$t = Invoke-Tick @{ LastVmState = 'Running'; VmState = 'Stopping'; VhdHasImage = $true }
if ([int]$t.SetupRebootCount -ne 1) { throw 'image + Stopping counts' }
$t = Invoke-Tick @{ LastVmState = 'Running'; VmState = 'Stopping'; VhdHasImage = $false; VhdFileSizeBytes = 100MB }
if ([int]$t.SetupRebootCount -ne 0) { throw 'empty VHD is WinPE churn' }
$t = Invoke-Tick @{ LastVmState = 'Off'; VmState = 'Running'; VhdHasImage = $true }
if ([int]$t.SetupRebootCount -ne 0) { throw 'Off→Running is start, not leave-Running' }
$t = Invoke-Tick @{ SetupRebootCount = 8 }
if ($t.FailReason) { throw 'at cap continues' }
$t = Invoke-Tick @{ SetupRebootCount = 9 }
if ($t.FailReason -cne 'REBOOT_LOOP') { throw 'past cap is a loop' }

$t = Invoke-Tick @{ LastVmState = 'Off'; VmState = 'Running'; DiskBootPreferred = $false; VhdHasImage = $false; VhdFileSizeBytes = 100MB }
if (-not [bool]$t.RearmNudge) { throw 'Off→Running re-arms while DVD first' }
$t = Invoke-Tick @{ LastVmState = 'Off'; VmState = 'Running'; DiskBootPreferred = $true }
if ([bool]$t.RearmNudge) { throw 'HDD-first does not re-arm' }

$t = Invoke-Tick @{ GuestUpSticky = $true; StallElapsedMinutes = 45; StallMinutes = 45; Cpu = 90 }
if ($t.FailReason -cne 'STALL') { throw 'Complete-without-handoff CEH spinner must stall' }
if ($t.FailMessage -notmatch '^STALL_SUSPECT:') { throw 'stall FailMessage prefix' }
$t = Invoke-Tick @{ GuestUpSticky = $true; StallElapsedMinutes = 45; StallMinutes = 45; SupervisorRunning = $true }
if ($t.FailReason) { throw 'Supervisor alive must extend stall, not fail' }

$t = Invoke-Tick @{ VhdFileSizeBytes = 36MB; VhdHasImage = $false; EmptyVhdRunningSeconds = 60 }
if ($t.FailReason) { throw 'empty VHD under budget' }
$t = Invoke-Tick @{ VhdFileSizeBytes = 36MB; VhdHasImage = $false; EmptyVhdRunningSeconds = 480 }
if ($t.FailReason -cne 'EMPTY_VHD') { throw 'empty VHD after Running budget' }
if ($t.FailMessage -notmatch '^EMPTY_VHD:') { throw 'empty-VHD FailMessage prefix' }

$t = Invoke-Tick @{ VmState = 'Paused' }
if ($t.FailReason -cne 'UNEXPECTED') { throw 'unexpected VM state' }

if ((Get-SmokeSuspendVmDecision -FailureMessage 'STALL_SUSPECT: no guest progress') -cne 'suspend') { throw 'stall suspends' }
if ((Get-SmokeSuspendVmDecision -FailureMessage 'Wall clock elapsed without guest evidence') -cne 'suspend') { throw 'wall suspends' }
if ((Get-SmokeSuspendVmDecision -FailureMessage 'REBOOT_LOOP: 9 setup reboots') -cne 'suspend') { throw 'reboot-loop suspends' }
if ((Get-SmokeSuspendVmDecision -FailureMessage 'EMPTY_VHD: disk never grew') -cne 'suspend') { throw 'empty-vhd suspends' }
if ((Get-SmokeSuspendVmDecision -FailureMessage 'Apply failed: 1') -cne 'skip') { throw 'Apply failure does not suspend' }
if ((Get-SmokeSuspendVmDecision -FailureMessage "Smoke acceptance requires outcome Complete, got 'Failed' (Failed/Reboot is not green)") -cne 'shutdown') {
    throw 'assert fail must ACPI-shutdown (leftover Running + TurnOff is DirtyShutdown / why-did-my-PC-restart)'
}
if ((Get-SmokeWatcherSpawnDecision -MarkerPidAlive $true) -cne 'skip') { throw 'live watcher is unique' }
if ((Get-SmokeWatcherSpawnDecision -MarkerPidAlive $false) -cne 'spawn') { throw 'dead marker respawns' }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('smoke-status-' + [guid]::NewGuid().ToString('N'))
$statusPath = Join-Path $tmp 'smoke-status.json'
try {
    Write-SmokeStatus -Path $statusPath -Phase apply -VmName 'winmint-smoke' `
        -StallMinutesLeft 45 -WallMinutesLeft 180 -LastHostLine 'Applying'
    $doc = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
    if ($doc.schemaVersion -cne 'winmint.smoke.status/v1') { throw 'schema' }
    if ($doc.phase -cne 'apply') { throw 'written phase' }
    if ($null -eq $doc.updatedAt) { throw 'updatedAt missing' }
    if ([int]$doc.waiterPid -ne [int]$PID) { throw "waiterPid should default to this pwsh (got $($doc.waiterPid))" }

    $watchParams = (Get-Command Get-SmokeWatchVerdict).Parameters.Keys
    if ($watchParams -match 'Pid') { throw 'Get-SmokeWatchVerdict must not take a PID list' }

    if ((Get-SmokeWatchVerdict -Phase green) -cne 'done') { throw 'green is done' }
    if ((Get-SmokeWatchVerdict -Phase failed) -cne 'done') { throw 'failed is done' }
    if ((Get-SmokeWatchVerdict -Phase assert) -cne 'done') { throw 'assert is done' }
    if ((Get-SmokeWatchVerdict -Phase apply -StatusAgeSeconds 99999) -cne 'continue') { throw 'apply may be silent for hours' }
    if ((Get-SmokeWatchVerdict -Phase apply -VmState Running -VhdFileSizeMB 36 -EmptyVhdRunningSeconds 480) -cne 'continue') { throw 'apply is host DISM, not empty-VHD' }
    if ((Get-SmokeWatchVerdict -Phase guest-up -VmState Running -VhdFileSizeMB 17000 -StatusAgeSeconds 5) -cne 'continue') { throw 'guest-up with fresh status is live' }
    if ((Get-SmokeWatchVerdict -Phase guest-up -StatusAgeSeconds 200) -cne 'harness-stale') { throw 'stale status after wait phases' }
    if ((Get-SmokeWatchVerdict -Phase vm-boot -VmState Running -VhdFileSizeMB 36 -EmptyVhdRunningSeconds 60) -cne 'continue') { throw 'empty VHD under budget' }
    if ((Get-SmokeWatchVerdict -Phase vm-boot -VmState Running -VhdFileSizeMB 36 -EmptyVhdRunningSeconds 480) -cne 'empty-vhd') { throw 'empty VHD after Running budget' }

    Write-SmokeStatus -Path $statusPath -Phase failed -VmName 'winmint-smoke' -RunId 'run-a' -LastHostLine 'old failure'
    $stale = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
    if ($stale.runId -cne 'run-a') { throw 'runId written to status' }
    if ((Get-SmokeWatchVerdict -Phase failed -StatusRunId 'run-a' -PriorRunId 'run-a') -cne 'awaiting-run') { throw 'prior-run failed is not done' }
    if ((Get-SmokeWatchVerdict -Phase failed -StatusRunId '' -PriorRunId '') -cne 'awaiting-run') { throw 'runId-less stale status is not done' }
    if ((Get-SmokeWatchVerdict -Phase failed -StatusRunId 'run-b' -PriorRunId 'run-a') -cne 'done') { throw 'new run failed is done' }
    if ((Get-SmokeWatchVerdict -Phase apply -StatusRunId 'run-b' -PriorRunId 'run-a' -StatusAgeSeconds 99999) -cne 'continue') { throw 'new run apply may be silent for hours' }

    $applyWork = Join-Path $tmp 'apply-work'
    New-Item -ItemType Directory -Force -Path $applyWork | Out-Null
    Set-Content -LiteralPath (Join-Path $applyWork 'apply-status.txt') -Value "stage=failed:AddQualityUpdates`nlog=x" -Encoding utf8
    '{"message":"combined LCU missing SSU"}' | Set-Content -LiteralPath (Join-Path $applyWork 'failure.json') -Encoding utf8
    if ((Get-WinMintApplyHostFailure -WorkDirectory $applyWork) -cne 'combined LCU missing SSU') { throw 'apply-status projects failure.json' }
    Set-Content -LiteralPath (Join-Path $applyWork 'apply-status.txt') -Value "stage=MountInstallWim`n" -Encoding utf8
    if ($null -ne (Get-WinMintApplyHostFailure -WorkDirectory $applyWork)) {
        throw 'Get-WinMintApplyHostFailure must ignore a live Apply'
    }

    $evDir = Join-Path $tmp 'guest-ev'
    New-Item -ItemType Directory -Force -Path $evDir | Out-Null
    '{"outcome":"Reboot"}' | Set-Content -LiteralPath (Join-Path $evDir 'evidence-newer-reboot.json') -Encoding utf8
    '{"outcome":"Complete"}' | Set-Content -LiteralPath (Join-Path $evDir 'evidence-older-complete.json') -Encoding utf8
    (Get-Item -LiteralPath (Join-Path $evDir 'evidence-newer-reboot.json')).LastWriteTimeUtc = [datetime]::UtcNow
    (Get-Item -LiteralPath (Join-Path $evDir 'evidence-older-complete.json')).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-2)
    $picked = Select-WinMintGuestEvidencePath -Directory $evDir
    if ($picked -notmatch 'evidence-older-complete') {
        throw "Select-WinMintGuestEvidencePath must prefer Complete over newer Reboot, got $picked"
    }

    $evNew = Join-Path $tmp 'guest-ev-newest'
    New-Item -ItemType Directory -Force -Path $evNew | Out-Null
    '{"outcome":"Complete"}' | Set-Content -LiteralPath (Join-Path $evNew 'evidence-20260101000000000-old.json') -Encoding utf8
    '{"outcome":"Complete","statusCode":"jobs.ok","phases":["jobs.ok"]}' |
        Set-Content -LiteralPath (Join-Path $evNew 'evidence-20260201000000000-new.json') -Encoding utf8
    $newest = Select-WinMintGuestEvidencePath -Directory $evNew
    if ($newest -notmatch 'evidence-20260201000000000-new') {
        throw "Select-WinMintGuestEvidencePath must pick newest Complete, got $newest"
    }

    $evRun = Join-Path $tmp 'guest-ev-runid'
    New-Item -ItemType Directory -Force -Path $evRun | Out-Null
    '{"outcome":"Complete","smokeRunId":"old-run"}' |
        Set-Content -LiteralPath (Join-Path $evRun 'evidence-20260101000000001.json') -Encoding utf8
    '{"outcome":"Complete","smokeRunId":"this-run","statusCode":"jobs.ok"}' |
        Set-Content -LiteralPath (Join-Path $evRun 'evidence-20260101000000002.json') -Encoding utf8
    if ($null -ne (Select-WinMintGuestEvidencePath -Directory $evRun -RequiredSmokeRunId 'missing')) {
        throw 'Select-WinMintGuestEvidencePath must reject when no evidence matches RequiredSmokeRunId'
    }
    $matched = Select-WinMintGuestEvidencePath -Directory $evRun -RequiredSmokeRunId 'this-run'
    if ($matched -notmatch 'evidence-20260101000000002') {
        throw "Select-WinMintGuestEvidencePath must pick matching smokeRunId, got $matched"
    }
    $noStamp = [pscustomobject]@{
        outcome    = 'Complete'
        statusCode = 'jobs.ok'
        phases     = @('shell.firstPaint', 'jobs.ok', 'oobe.dismiss')
    }
    if (Test-WinMintGuestEvidenceTerminal -EvidenceDoc $noStamp `
            -LiveShell 'explorer.exe' -SupervisorRunning:$false -RequiredSmokeRunId 'this-run') {
        throw 'Complete without matching smokeRunId must fail when RequiredSmokeRunId is set'
    }

    $staleComplete = [pscustomobject]@{
        outcome    = 'Complete'
        statusCode = 'jobs.ok'
        phases     = @('shell.firstPaint', 'jobs.ok')
    }
    if (Test-WinMintGuestEvidenceTerminal -EvidenceDoc $staleComplete `
            -LiveShell 'C:\Windows\WinMint\Supervisor.exe' -SupervisorRunning:$true) {
        throw 'Complete evidence must not pass while Supervisor is still running'
    }
    $noDismiss = [pscustomobject]@{
        outcome    = 'Complete'
        statusCode = 'jobs.ok'
        phases     = @('shell.firstPaint', 'jobs.ok')
    }
    if (Test-WinMintGuestEvidenceTerminal -EvidenceDoc $noDismiss `
            -LiveShell 'explorer.exe' -SupervisorRunning:$false) {
        throw 'Complete evidence without oobe.dismiss must fail handoff gate'
    }
    $handoff = [pscustomobject]@{
        outcome    = 'Complete'
        statusCode = 'jobs.ok'
        phases     = @('shell.firstPaint', 'jobs.ok', 'oobe.dismiss')
    }
    if (-not (Test-WinMintGuestEvidenceTerminal -EvidenceDoc $handoff `
            -LiveShell 'explorer.exe' -SupervisorRunning:$false)) {
        throw 'Complete + explorer shell + no Supervisor must pass handoff gate'
    }
    if (Test-WinMintGuestEvidenceTerminal -EvidenceDoc $handoff `
            -LiveShell 'explorer.exe' -SupervisorRunning:$true) {
        throw 'Supervisor running must fail handoff gate even with Complete evidence'
    }
    if (Test-WinMintGuestEvidenceTerminal -EvidenceDoc $handoff `
            -LiveShell 'explorer.exe' -SupervisorRunning:$false -ExplorerRunning $false) {
        throw 'live mode must fail-close when explorer.exe is not running'
    }
    if (-not (Test-WinMintGuestEvidenceTerminal -EvidenceDoc $handoff `
            -LiveShell 'explorer.exe' -SupervisorRunning:$false -ExplorerRunning $true)) {
        throw 'live mode must pass when explorer.exe is running'
    }

    $credDir = Join-Path $tmp 'creds'
    New-Item -ItemType Directory -Force -Path $credDir | Out-Null
    '{"schemaVersion":"winmint.profile/v1","account":{"username":"winmint","password":"inline"}}' |
        Set-Content -LiteralPath (Join-Path $credDir 'inline.json') -Encoding utf8
    $inlineCred = Resolve-WinMintSmokeGuestCredential -ProfilePath (Join-Path $credDir 'inline.json')
    if ($inlineCred.UserName -cne 'winmint') { throw 'inline password username' }
    $secret = Join-Path $credDir 'secret.txt'
    Set-Content -LiteralPath $secret -Value "path-pass`n" -NoNewline -Encoding utf8
    '{"schemaVersion":"winmint.profile/v1","account":{"username":"yanai","passwordPath":"secret.txt"}}' |
        Set-Content -LiteralPath (Join-Path $credDir 'path.json') -Encoding utf8
    $pathCred = Resolve-WinMintSmokeGuestCredential -ProfilePath (Join-Path $credDir 'path.json')
    if ($pathCred.UserName -cne 'yanai') { throw 'passwordPath username' }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pathCred.Password)
    try {
        if (([Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)) -cne 'path-pass') { throw 'passwordPath contents' }
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    '{"schemaVersion":"winmint.profile/v1","account":{"username":"yanai","passwordPath":"missing.password"}}' |
        Set-Content -LiteralPath (Join-Path $credDir 'missing.json') -Encoding utf8
    try {
        $null = Resolve-WinMintSmokeGuestCredential -ProfilePath (Join-Path $credDir 'missing.json')
        throw 'missing passwordPath must throw'
    } catch {
        if ($_.Exception.Message -notmatch 'missing file') { throw "missing passwordPath message: $($_.Exception.Message)" }
    }
    '{"schemaVersion":"winmint.profile/v1","account":{"username":"yanai","passwordPath":"\\scratch\\pw"}}' |
        Set-Content -LiteralPath (Join-Path $credDir 'rooted.json') -Encoding utf8
    try {
        $null = Resolve-WinMintSmokeGuestCredential -ProfilePath (Join-Path $credDir 'rooted.json')
        throw 'root-relative passwordPath must throw'
    } catch {
        if ($_.Exception.Message -notmatch 'root-relative') { throw "rooted passwordPath message: $($_.Exception.Message)" }
    }

    $pixels = [byte[]]::new(8)
    $bmp = ConvertTo-WinMintBmp565 -PixelData $pixels -Width 2 -Height 2
    if ($bmp.Length -ne (14 + 40 + 12 + 8)) { throw "BMP size $($bmp.Length)" }
    if ($bmp[0] -ne 0x42 -or $bmp[1] -ne 0x4D) { throw 'BMP magic' }
    $fileSize = [BitConverter]::ToInt32($bmp, 2)
    if ($fileSize -ne $bmp.Length) { throw "BMP file size $fileSize" }
    $height = [BitConverter]::ToInt32($bmp, 22)
    if ($height -ne -2) { throw "BMP height $height (want top-down -2)" }

    $blocked = Join-Path $tmp 'blocked'
    Set-Content -LiteralPath $blocked -Value 'not-a-dir' -Encoding utf8
    try {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        Write-SmokeStatus -Path (Join-Path $blocked 'smoke-status.json') -Phase failed `
            -VmName 'winmint-smoke' -StallMinutesLeft 0 -WallMinutesLeft 0 -LastHostLine 'fail'
    } finally {
        $ErrorActionPreference = $prevEap
    }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Start-SmokeMonitor -VmName 'winmint-smoke' -ConnectExe 'C:\no-such-vmconnect.exe'
$script:launched = $null
Start-SmokeMonitor -VmName 'winmint-smoke' -ConnectExe $PSCommandPath -Launcher {
    param($Exe, $VmName)
    $script:launched = @{ Exe = $Exe; VmName = $VmName }
}
if ($null -eq $script:launched) { throw 'Launcher not called for existing ConnectExe' }
if ($script:launched.VmName -cne 'winmint-smoke') { throw 'vmconnect vm name' }
Start-SmokeMonitor -VmName 'x' -ConnectExe $PSCommandPath -Launcher { throw 'boom' }

Write-Output 'Test-SmokeStatus ok'
exit 0
