#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools/vm/SmokeStatus.ps1')

$smoke = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Invoke-Smoke.ps1') -Raw -Encoding utf8
if ($smoke -notmatch 'tools[/\\]vm[/\\]SmokeStatus\.ps1') { throw 'Invoke-Smoke must dot-source SmokeStatus.ps1' }
if ($smoke -notmatch 'Get-WinMintApplyHostFailure') { throw 'Apply wait must use Get-WinMintApplyHostFailure' }
if ($smoke -notmatch "Resolve-SmokePhase -HostStage failed") { throw 'Apply/wait failures must write phase=failed' }
if ($smoke -match 'Get-Content[^\n]*smoke-status\.json') { throw 'must not read smoke-status.json as control plane' }
if ($smoke -notmatch 'Get-SmokeWatchVerdict') { throw 'Invoke-Smoke wait loop must call Get-SmokeWatchVerdict' }
if ($smoke -notmatch 'EMPTY_VHD:') { throw 'empty-VHD throw prefix missing (operator copy)' }
if ($smoke -notmatch '\[Diagnostics\.Stopwatch\]') { throw 'stall/wall/empty-vhd must use Stopwatch, not UtcNow deadlines' }
if ($smoke -notmatch 'Select-WinMintGuestEvidencePath') { throw 'guest evidence must select by outcome, not LastWriteTime' }
if ($smoke -notmatch 'Test-WinMintGuestEvidenceTerminal') {
    throw 'Invoke-Smoke must fail-close Complete evidence with Test-WinMintGuestEvidenceTerminal'
}
if ($smoke -match 'process-exited-early' -or $smoke -match 'Find-SmokePids') {
    throw 'Invoke-Smoke must not infer harness death from process lists'
}
if ($smoke -notmatch 'Get-SmokeWaitPhaseSticky') {
    throw 'Invoke-Smoke wait loop must use Get-SmokeWaitPhaseSticky (sticky guest-up)'
}
if ($smoke -notmatch 'Get-SmokeRunIdStampDecision') {
    throw 'Invoke-Smoke must retry smoke-run.id via Get-SmokeRunIdStampDecision'
}
if ($smoke -notmatch 'SmokeRunIdStamped') {
    throw 'Invoke-Smoke must track SmokeRunIdStamped across wait polls'
}
if ($smoke -notmatch "Remove-Item[^\n]*priorProjections" -or $smoke -notmatch "'evidence\.json', 'stages\.json'") {
    throw 'Invoke-Smoke must clear prior-run Apply projections (apply-status/failure/evidence/stages/expected) before Apply'
}
if ($smoke -notmatch 'if \(\$SkipApply\) \{ Resolve-WinMintOutputIso') {
    throw 'Full runs must not resolve the Output ISO before Apply (stale winmint_*.iso would fail-close a fresh Apply)'
}
if ($smoke.IndexOf('Write-SmokeStatus') -gt $smoke.IndexOf('Watch-SmokeHost.ps1')) {
    throw 'Invoke-Smoke must write this run''s status before spawning Watch-SmokeHost (stale-status guard)'
}
if ($smoke -notmatch 'Resolve-WinMintSmokeGuestCredential') {
    throw 'Invoke-Smoke must resolve guest credentials via Resolve-WinMintSmokeGuestCredential'
}
if ($smoke -notmatch 'Get-SmokeStallExtendDecision') {
    throw 'Invoke-Smoke wait loop must use Get-SmokeStallExtendDecision'
}
if ($smoke -notmatch 'Get-SmokeSetupRebootTransition') {
    throw 'Invoke-Smoke must count setup reboots via Get-SmokeSetupRebootTransition'
}
if ($smoke -notmatch 'Get-SmokeRebootLoopVerdict') {
    throw 'Invoke-Smoke must fail-fast reboot loops via Get-SmokeRebootLoopVerdict'
}
if ($smoke -notmatch 'Save-SmokeVmScreenshot') {
    throw 'Invoke-Smoke must capture a VM console screenshot on failure/half-stall'
}
if ($smoke -notmatch 'Get-SmokeSuspendVmDecision') {
    throw 'Invoke-Smoke must Suspend-VM on stall/wall/reboot-loop via Get-SmokeSuspendVmDecision'
}
if ($smoke -notmatch 'Get-SmokeNudgeRearmDecision') {
    throw 'Invoke-Smoke must re-arm the DVD nudge via Get-SmokeNudgeRearmDecision'
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

$justfile = Get-Content -LiteralPath (Join-Path $repo 'Justfile') -Raw -Encoding utf8
if ($justfile -notmatch 'NonInteractive') {
    throw 'just smoke / smoke-assert must pass -NonInteractive'
}
if ($justfile -notmatch 'STALL=') {
    throw 'just smoke must expose STALL'
}
if ($justfile -notmatch 'MONITOR="" STALL="45"') {
    throw 'just smoke STALL must come after MONITOR (positional 5 is MONITOR, not StallMinutes)'
}
if ($justfile -notmatch "just smoke '[^']+' '{{WORK}}' '[^']+' '{{WALL}}' '{{MONITOR}}' '{{STALL}}'") {
    throw 'just smoke-maintainer must pass MONITOR then STALL (empty MONITOR must not become -StallMinutes)'
}

$watch = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Watch-SmokeHost.ps1') -Raw -Encoding utf8
if ($watch -notmatch 'Get-SmokeWatchVerdict') {
    throw 'Watch-SmokeHost must call Get-SmokeWatchVerdict'
}
if ($watch -notmatch 'PriorRunId') {
    throw 'Watch-SmokeHost must pass -PriorRunId'
}
if ($watch -notmatch 'verdict') {
    throw 'Watch-SmokeHost must display the verdict'
}
if ($watch -notmatch 'Format-WinMintHostWatch') {
    throw 'Watch-SmokeHost must render via Format-WinMintHostWatch'
}
$spawnAt = $smoke.IndexOf('Watch-SmokeHost.ps1')
if ($spawnAt -lt 0) { throw 'Invoke-Smoke must spawn Watch-SmokeHost' }
$spawn = $smoke.Substring($spawnAt, [Math]::Min(400, $smoke.Length - $spawnAt))
if ($spawn -notmatch 'PriorRunId') {
    throw 'spawned watcher must receive leftover or empty -PriorRunId (parent already stamped)'
}
if ($spawn -match '\$runId') {
    throw 'spawned watcher must not receive this run''s already-written runId as PriorRunId'
}
if ($watch -notmatch 'PSBoundParameters' -or $watch -notmatch 'ContainsKey') {
    throw 'Watch-SmokeHost must not treat the post-stamp file as PriorRunId when the parent bound leftover/empty'
}

function Assert-Eq($Actual, $Expected, [string] $Message) {
    if ($Actual -cne $Expected) { throw "$Message (got '$Actual', expected '$Expected')" }
}

Assert-Eq (Resolve-SmokePhase -HostStage apply) apply 'apply stage'
Assert-Eq (Resolve-SmokePhase -HostStage assert) assert 'assert stage'
Assert-Eq (Resolve-SmokePhase -HostStage green) green 'green stage'
Assert-Eq (Resolve-SmokePhase -HostStage failed) failed 'failed stage'
Assert-Eq (Resolve-SmokePhase -HostStage wait -VmState Stopping) setup-reboot 'setup reboot'
Assert-Eq (Resolve-SmokePhase -HostStage wait -VmState Off) setup-reboot 'setup off'
Assert-Eq (Resolve-SmokePhase -HostStage wait -VmState Starting) setup-reboot 'setup starting'
Assert-Eq (Resolve-SmokePhase -HostStage wait -VmState Running -VhdFileSizeBytes 100MB) vm-boot 'empty VHD'
Assert-Eq (Resolve-SmokePhase -HostStage wait -VmState Running -VhdFileSizeBytes 1GB) winpe-apply 'VHD has image'
Assert-Eq (Resolve-SmokePhase -HostStage wait -VmState Running -VhdFileSizeBytes 1GB -HeartbeatOk) guest-up 'heartbeat wins VHD'
Assert-Eq (Resolve-SmokePhase -HostStage wait -VmState Running -HeartbeatOk -EvidenceReady) guest-up 'evidence ready still guest-up until HostStage assert'

# Sticky guest-up: after 2 consecutive heartbeat OK while Running, stay guest-up on a blip.
$sticky1 = Get-SmokeWaitPhaseSticky -VmState Running -VhdFileSizeBytes 1GB -HeartbeatOk:$true `
    -GuestUpSticky:$false -ConsecutiveHeartbeatOk 0
Assert-Eq $sticky1.Phase guest-up 'first HB still guest-up'
Assert-Eq ([string]$sticky1.GuestUpSticky) 'False' 'sticky arms at 2'
Assert-Eq ([int]$sticky1.ConsecutiveHeartbeatOk) 1 'consec after first HB'
$sticky2 = Get-SmokeWaitPhaseSticky -VmState Running -VhdFileSizeBytes 1GB -HeartbeatOk:$true `
    -GuestUpSticky:$false -ConsecutiveHeartbeatOk 1
Assert-Eq $sticky2.Phase guest-up 'second HB guest-up'
Assert-Eq ([string]$sticky2.GuestUpSticky) 'True' 'sticky armed'
$stickyBlip = Get-SmokeWaitPhaseSticky -VmState Running -VhdFileSizeBytes 1GB -HeartbeatOk:$false `
    -GuestUpSticky:$true -ConsecutiveHeartbeatOk 2
Assert-Eq $stickyBlip.Phase guest-up 'sticky survives HB blip'
Assert-Eq (Get-SmokeWaitPhaseSticky -VmState Off -VhdFileSizeBytes 1GB -HeartbeatOk:$false `
    -GuestUpSticky:$true -ConsecutiveHeartbeatOk 2).Phase setup-reboot 'Off clears sticky path'
Assert-Eq ([string](Get-SmokeWaitPhaseSticky -VmState Off -VhdFileSizeBytes 1GB -HeartbeatOk:$false `
    -GuestUpSticky:$true -ConsecutiveHeartbeatOk 2).GuestUpSticky) 'False' 'Off clears sticky flag'

Assert-Eq (Get-SmokeRunIdStampDecision -AlreadyStamped:$true -HeartbeatOk:$true) skip 'already stamped'
Assert-Eq (Get-SmokeRunIdStampDecision -AlreadyStamped:$false -HeartbeatOk:$false) skip 'no heartbeat yet'
Assert-Eq (Get-SmokeRunIdStampDecision -AlreadyStamped:$false -HeartbeatOk:$true) try-stamp 'first contact'

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('smoke-status-' + [guid]::NewGuid().ToString('N'))
$statusPath = Join-Path $tmp 'smoke-status.json'
try {
    Write-SmokeStatus -Path $statusPath -Phase apply -VmName 'winmint-smoke' `
        -StallMinutesLeft 45 -WallMinutesLeft 180 -LastHostLine 'Applying'
    $doc = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
    Assert-Eq $doc.schemaVersion 'winmint.smoke.status/v1' 'schema'
    Assert-Eq $doc.phase 'apply' 'written phase'
    Assert-Eq $doc.vmName 'winmint-smoke' 'vm name'
    if ($null -eq $doc.updatedAt) { throw 'updatedAt missing' }
    if ([int]$doc.waiterPid -ne [int]$PID) { throw "waiterPid should default to this pwsh (got $($doc.waiterPid))" }

    $watchParams = (Get-Command Get-SmokeWatchVerdict).Parameters.Keys
    if ($watchParams -match 'Pid') { throw 'Get-SmokeWatchVerdict must not take a PID list' }

    Assert-Eq (Get-SmokeWatchVerdict -Phase green) done 'green is done'
    Assert-Eq (Get-SmokeWatchVerdict -Phase failed) done 'failed is done'
    Assert-Eq (Get-SmokeWatchVerdict -Phase assert) done 'assert is done'
    Assert-Eq (Get-SmokeWatchVerdict -Phase apply -StatusAgeSeconds 99999) continue 'apply may be silent for hours'
    Assert-Eq (Get-SmokeWatchVerdict -Phase apply -VmState Running -VhdFileSizeMB 36 -EmptyVhdRunningSeconds 480) continue 'apply is host DISM, not empty-VHD'
    Assert-Eq (Get-SmokeWatchVerdict -Phase guest-up -VmState Running -VhdFileSizeMB 17000 -StatusAgeSeconds 5) continue 'guest-up with fresh status is live (not missing PIDs)'
    Assert-Eq (Get-SmokeWatchVerdict -Phase winpe-apply -VmState Running -VhdFileSizeMB 2048 -StatusAgeSeconds 5) continue 'VHD growth is WinPE apply progress'
    Assert-Eq (Get-SmokeWatchVerdict -Phase setup-reboot -VmState Off -VhdFileSizeMB 36 -EmptyVhdRunningSeconds 480) continue 'Off is setup reboot, not empty-VHD'
    Assert-Eq (Get-SmokeWatchVerdict -Phase guest-up -StatusAgeSeconds 200) harness-stale 'stale status after wait phases'
    Assert-Eq (Get-SmokeWatchVerdict -Phase vm-boot -VmState Running -VhdFileSizeMB 36 -EmptyVhdRunningSeconds 60) continue 'empty VHD under budget'
    Assert-Eq (Get-SmokeWatchVerdict -Phase vm-boot -VmState Running -VhdFileSizeMB 36 -EmptyVhdRunningSeconds 480) empty-vhd 'empty VHD after Running budget'

    # Run identity: a status carried over from a prior run is awaiting-run, never done (22 Aug false-terminal).
    Write-SmokeStatus -Path $statusPath -Phase failed -VmName 'winmint-smoke' -RunId 'run-a' -LastHostLine 'old failure'
    $stale = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
    Assert-Eq $stale.runId 'run-a' 'runId written to status'
    Assert-Eq (Get-SmokeWatchVerdict -Phase failed -StatusRunId 'run-a' -PriorRunId 'run-a') awaiting-run 'prior-run failed is not done'
    Assert-Eq (Get-SmokeWatchVerdict -Phase failed -StatusRunId '' -PriorRunId '') awaiting-run 'runId-less stale status is not done'
    Assert-Eq (Get-SmokeWatchVerdict -Phase failed -StatusRunId 'run-b' -PriorRunId 'run-a') done 'new run failed is done'
    Assert-Eq (Get-SmokeWatchVerdict -Phase apply -StatusRunId 'run-b' -PriorRunId 'run-a' -StatusAgeSeconds 99999) continue 'new run apply may be silent for hours'

    $applyWork = Join-Path $tmp 'apply-work'
    New-Item -ItemType Directory -Force -Path $applyWork | Out-Null
    Set-Content -LiteralPath (Join-Path $applyWork 'apply-status.txt') -Value "stage=failed:AddQualityUpdates`nlog=x" -Encoding utf8
    '{"message":"combined LCU missing SSU"}' | Set-Content -LiteralPath (Join-Path $applyWork 'failure.json') -Encoding utf8
    Assert-Eq (Get-WinMintApplyHostFailure -WorkDirectory $applyWork) 'combined LCU missing SSU' 'apply-status projects failure.json'
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

    # Newest Complete wins when multiple Complete files exist (stale prior-tenure evidence).
    $evNew = Join-Path $tmp 'guest-ev-newest'
    New-Item -ItemType Directory -Force -Path $evNew | Out-Null
    '{"outcome":"Complete"}' | Set-Content -LiteralPath (Join-Path $evNew 'evidence-20260101000000000-old.json') -Encoding utf8
    '{"outcome":"Complete","statusCode":"jobs.ok","phases":["jobs.ok"]}' |
        Set-Content -LiteralPath (Join-Path $evNew 'evidence-20260201000000000-new.json') -Encoding utf8
    $newest = Select-WinMintGuestEvidencePath -Directory $evNew
    if ($newest -notmatch 'evidence-20260201000000000-new') {
        throw "Select-WinMintGuestEvidencePath must pick newest Complete, got $newest"
    }

    # RequiredSmokeRunId ignores stale Complete from another Smoke run.
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
    if (-not (Test-WinMintGuestEvidenceTerminal -EvidenceDoc $handoff `
            -LiveShell 'explorer.exe' -SupervisorRunning:$false)) {
        throw 'omitting ExplorerRunning must stay neutral for static fixtures'
    }
    if (Test-WinMintGuestEvidenceTerminal -EvidenceDoc $handoff `
            -LiveShell 'explorer.exe' -SupervisorRunning:$false -ExplorerRunning $false) {
        throw 'live mode must fail-close when explorer.exe is not running'
    }
    if (-not (Test-WinMintGuestEvidenceTerminal -EvidenceDoc $handoff `
            -LiveShell 'explorer.exe' -SupervisorRunning:$false -ExplorerRunning $true)) {
        throw 'live mode must pass when explorer.exe is running'
    }

    # Credentials: password, passwordPath (relative), missing file, root-relative.
    $credDir = Join-Path $tmp 'creds'
    New-Item -ItemType Directory -Force -Path $credDir | Out-Null
    '{"schemaVersion":"winmint.profile/v1","account":{"username":"winmint","password":"inline"}}' |
        Set-Content -LiteralPath (Join-Path $credDir 'inline.json') -Encoding utf8
    $inlineCred = Resolve-WinMintSmokeGuestCredential -ProfilePath (Join-Path $credDir 'inline.json')
    Assert-Eq $inlineCred.UserName 'winmint' 'inline password username'
    $secret = Join-Path $credDir 'secret.txt'
    Set-Content -LiteralPath $secret -Value "path-pass`n" -NoNewline -Encoding utf8
    '{"schemaVersion":"winmint.profile/v1","account":{"username":"yanai","passwordPath":"secret.txt"}}' |
        Set-Content -LiteralPath (Join-Path $credDir 'path.json') -Encoding utf8
    $pathCred = Resolve-WinMintSmokeGuestCredential -ProfilePath (Join-Path $credDir 'path.json')
    Assert-Eq $pathCred.UserName 'yanai' 'passwordPath username'
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pathCred.Password)
    try {
        Assert-Eq ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)) 'path-pass' 'passwordPath contents'
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

    # Stall / reboot-loop / progress / nudge / suspend / watcher spawn.
    Assert-Eq (Get-SmokeStallExtendDecision -VmState Starting -Cpu 0 -GuestUpSticky $false -GuestProgress $false) extend 'reboot churn extends'
    Assert-Eq (Get-SmokeStallExtendDecision -VmState Running -Cpu 40 -GuestUpSticky $false -GuestProgress $false) extend 'pre-guest-up CPU extends'
    Assert-Eq (Get-SmokeStallExtendDecision -VmState Running -Cpu 90 -GuestUpSticky $true -GuestProgress $false) hold 'CEH spinner after guest-up does not extend'
    Assert-Eq (Get-SmokeStallExtendDecision -VmState Running -Cpu 0 -GuestUpSticky $true -GuestProgress $true) extend 'guest progress extends after guest-up'
    Assert-Eq (Get-SmokeGuestProgressDecision -LastFingerprint '1:Reboot' -Fingerprint '1:Reboot' -SupervisorRunning $false) idle 'same evidence is idle'
    Assert-Eq (Get-SmokeGuestProgressDecision -LastFingerprint '1:Reboot' -Fingerprint '2:Complete' -SupervisorRunning $false) progress 'new evidence is progress'
    Assert-Eq (Get-SmokeGuestProgressDecision -LastFingerprint '' -Fingerprint '' -SupervisorRunning $true) progress 'Supervisor alive is progress'
    Assert-Eq (Get-SmokeSetupRebootTransition -LastVmState Running -VmState Stopping -VhdHasImage $true) count 'image + Stopping counts'
    Assert-Eq (Get-SmokeSetupRebootTransition -LastVmState Running -VmState Stopping -VhdHasImage $false) skip 'empty VHD is WinPE churn'
    Assert-Eq (Get-SmokeSetupRebootTransition -LastVmState Off -VmState Running -VhdHasImage $true) skip 'Off→Running is start, not leave-Running'
    Assert-Eq (Get-SmokeRebootLoopVerdict -SetupRebootCount 8 -MaxSetupReboots 8) continue 'at cap continues'
    Assert-Eq (Get-SmokeRebootLoopVerdict -SetupRebootCount 9 -MaxSetupReboots 8) reboot-loop 'past cap is a loop'
    Assert-Eq (Get-SmokeNudgeRearmDecision -LastVmState Off -VmState Running -DiskBootPreferred $false) rearm 'Off→Running re-arms while DVD first'
    Assert-Eq (Get-SmokeNudgeRearmDecision -LastVmState Off -VmState Running -DiskBootPreferred $true) skip 'HDD-first does not re-arm'
    Assert-Eq (Get-SmokeSuspendVmDecision -FailureMessage 'STALL_SUSPECT: no guest progress') suspend 'stall suspends'
    Assert-Eq (Get-SmokeSuspendVmDecision -FailureMessage 'Wall clock elapsed without guest evidence') suspend 'wall suspends'
    Assert-Eq (Get-SmokeSuspendVmDecision -FailureMessage 'REBOOT_LOOP: 9 setup reboots') suspend 'reboot-loop suspends'
    Assert-Eq (Get-SmokeSuspendVmDecision -FailureMessage 'Apply failed: 1') skip 'Apply failure does not suspend'
    Assert-Eq (Get-SmokeWatcherSpawnDecision -MarkerPidAlive $true) skip 'live watcher is unique'
    Assert-Eq (Get-SmokeWatcherSpawnDecision -MarkerPidAlive $false) spawn 'dead marker respawns'

    $pixels = [byte[]]::new(8) # 2x2 RGB565, stride 4
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
Assert-Eq $script:launched.VmName 'winmint-smoke' 'vmconnect vm name'
Start-SmokeMonitor -VmName 'x' -ConnectExe $PSCommandPath -Launcher { throw 'boom' }

Write-Output 'Test-SmokeStatus ok'
exit 0
