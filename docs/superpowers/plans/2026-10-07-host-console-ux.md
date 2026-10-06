# Host console UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make elevated Apply / Smoke / Watch host output human-readable using native PowerShell 7.6+ progress and `$PSStyle`, while keeping a plain stage-log trail for agents and a future Wizard ISO-build tail.

**Architecture:** One helper seam (`Write-WinMintHostProgress.ps1`) owns console vs trail. `Invoke-WinMintLoggedKernel` heartbeats go to the log file and `Write-Progress`, not scrolling `Write-Host`. Watch filters heartbeat lines and spawns through `wt.exe` when present (Watch self-stamps its PID marker).

**Tech Stack:** PowerShell 7.6+, `$PSStyle`, `Write-Progress` Minimal + OSC indicator when interactive/VT, Windows Terminal `wt.exe`, existing contract tests under `tests/contract/`.

**Spec:** [docs/superpowers/specs/2026-10-07-host-console-ux-design.md](../specs/2026-10-07-host-console-ux-design.md)

## Global Constraints

- `#requires -Version 7.6` on touched host/servicing scripts
- No Spectre / OpenTUI / new NuGet packages for host UX
- Do not change `apply-status.txt` keys: `updated`, `stage`, `log`
- Do not invent Smoke wait `PercentComplete`
- Do not auto-spawn Watch from `just check`
- Do not reopen Orchestrator UAC `still`/`quiet` protocol or maintainer-check tokens
- Trail heartbeats stay in stage logs; console must not `Write-Host` each tick
- Wizard Avalonia UI is out of scope
- Commits only when the human asks

## File map

| File | Responsibility |
|------|----------------|
| `tools/host/Write-WinMintHostProgress.ps1` | Phase, progress, heartbeat, trail filter, watch format, watch spawn |
| `tools/host/Watch-Host.ps1` | Own-console refresh; filtered tail; optional `-MarkerPath` self-stamp |
| `servicing/Invoke-ServicingPlan.ps1` | `Invoke-WinMintLoggedKernel` uses heartbeat helper |
| `servicing/Add-QualityUpdates.ps1` | Hash % via helper progress on console; milestones stay `Write-Output` |
| `servicing/Resolve-WinMintQualityUpdate.ps1` | BITS / expand wait chatter → progress on console; start/ok stay visible |
| `tools/vm/Invoke-Smoke.ps1` | Call `Start-WinMintHostWatchProcess` instead of raw `Start-Process pwsh` |
| `tools/apply/Invoke-HostApply.ps1` | Route remaining banner lines through `Write-WinMintHostPhase` where cheap |
| `tests/contract/Test-WinMintHostProgress.ps1` | Contracts for helper, kernel heartbeat, filter, wt spawn fallback |
| `tests/contract/Test-SmokeStatus.ps1` | Spawn still unique; accepts wt helper path |

---

### Task 1: Helper heartbeat, filter, OSC init

**Files:**
- Modify: `tools/host/Write-WinMintHostProgress.ps1`
- Modify: `tests/contract/Test-WinMintHostProgress.ps1`

**Interfaces:**
- Consumes: existing `Initialize-WinMintHostProgress`, `Write-WinMintHostProgress`
- Produces:
  - `Test-WinMintTrailHeartbeatLine [-Line <string>]` → `[bool]`
  - `Select-WinMintWatchLogTail [-Lines <string[]>] [-Count <int>]` → `[string[]]`
  - `Write-WinMintHostHeartbeat -Opcode <string> -ElapsedSeconds <int> [-LogWriter <IO.TextWriter>]` → writes trail line; updates progress status; **no** `Write-Host` of the heartbeat

- [ ] **Step 1: Extend the contract test (fail first)**

In `tests/contract/Test-WinMintHostProgress.ps1`, after the existing Spectre/Clear-Host checks, add:

```powershell
if ($helper -notmatch 'function Write-WinMintHostHeartbeat') { throw 'helper must define Write-WinMintHostHeartbeat' }
if ($helper -notmatch 'function Test-WinMintTrailHeartbeatLine') { throw 'helper must define Test-WinMintTrailHeartbeatLine' }
if ($helper -notmatch 'function Select-WinMintWatchLogTail') { throw 'helper must define Select-WinMintWatchLogTail' }
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
```

- [ ] **Step 2: Run contract to verify fail**

Run: `pwsh -NoProfile -File tests/contract/Test-WinMintHostProgress.ps1`

Expected: FAIL on missing `Write-WinMintHostHeartbeat` (or detector).

- [ ] **Step 3: Implement helper APIs**

In `tools/host/Write-WinMintHostProgress.ps1`:

```powershell
function Test-WinMintHostProgressInteractive {
    try {
        return -not [Console]::IsOutputRedirected -and $Host.UI.SupportsVirtualTerminal
    }
    catch {
        return $false
    }
}

function Initialize-WinMintHostProgress {
    if ($script:WinMintHostProgressReady) { return }
    $script:WinMintHostProgressReady = $true
    try {
        $PSStyle.Progress.View = 'Minimal'
        if (Test-WinMintHostProgressInteractive) {
            $PSStyle.Progress.UseOSCIndicator = $true
        }
    }
    catch {
        Write-Debug "PSStyle.Progress: $_"
    }
}

function Test-WinMintTrailHeartbeatLine {
    param([Parameter(Mandatory)] [string] $Line)
    return [bool]($Line -match '^\S+ running \d+s$')
}

function Select-WinMintWatchLogTail {
    param(
        [string[]] $Lines = @(),
        [int] $Count = 8
    )
    $kept = @(
        $Lines |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not (Test-WinMintTrailHeartbeatLine -Line $_) }
    )
    if ($kept.Count -le $Count) { return $kept }
    return @($kept | Select-Object -Last $Count)
}

function Write-WinMintHostHeartbeat {
    param(
        [Parameter(Mandatory)] [string] $Opcode,
        [Parameter(Mandatory)] [int] $ElapsedSeconds,
        [IO.TextWriter] $LogWriter = $null,
        [string] $Activity = 'Apply'
    )
    Initialize-WinMintHostProgress
    $text = "$Opcode running ${ElapsedSeconds}s"
    if ($null -ne $LogWriter) {
        $LogWriter.WriteLine($text)
    }
    Write-WinMintHostProgress -Activity $Activity -Status $text
}
```

- [ ] **Step 4: Re-run contract**

Run: `pwsh -NoProfile -File tests/contract/Test-WinMintHostProgress.ps1`

Expected: PASS through the new assertions (later tasks may still be untouched).

- [ ] **Step 5: Commit (only if human asked)**

```text
feat(host): trail heartbeat helper and watch log filter
```

---

### Task 2: Logged kernel uses heartbeat helper

**Files:**
- Modify: `servicing/Invoke-ServicingPlan.ps1` (function `Invoke-WinMintLoggedKernel`, ~lines 23–77)
- Modify: `tests/contract/Test-WinMintHostProgress.ps1`

**Interfaces:**
- Consumes: `Write-WinMintHostHeartbeat` from helper (dot-source helper before logged kernel runs — plan already dots helper for phases; ensure logged-kernel path can call it, or inline the same trail/progress split if the nested runspace cannot see the function)
- Produces: stage log still contains `ProbeOp running`; heartbeat path must not call `Write-Host` for that line

**Runspace note:** `Invoke-WinMintLoggedKernel` runs in the elevated plan process (same session as the helper if `. Write-WinMintHostProgress.ps1` already ran at plan top). Confirm plan script already dots the helper near other host-phase calls; if not, add `. (Join-Path $PSScriptRoot '..\tools\host\Write-WinMintHostProgress.ps1')` once at script top of `Invoke-ServicingPlan.ps1`.

- [ ] **Step 1: Tighten contract**

Replace the weak `running \$` check with:

```powershell
if ($plan -notmatch 'Write-WinMintHostHeartbeat') { throw 'logged kernel must call Write-WinMintHostHeartbeat' }
# Heartbeat must not Write-Host the running line (trail + progress only).
$kernelFn = [regex]::Match($plan, '(?ms)^function Invoke-WinMintLoggedKernel \{.*?^\}').Value
if ($kernelFn -match 'Write-Host \$text' -and $kernelFn -match 'running') {
    # Allow Write-Host for teed kernel output; forbid Write-Host of the constructed heartbeat.
}
if ($kernelFn -match 'Write-Host \"\$Opcode running' -or $kernelFn -match "Write-Host \(`"?\`$Opcode running") {
    throw 'logged kernel must not Write-Host heartbeat'
}
if ($kernelFn -match 'Write-Host \$text' ) {
    # still OK for tee — ensure heartbeat uses helper:
}
if ($kernelFn -notmatch 'Write-WinMintHostHeartbeat') { throw 'logged kernel missing heartbeat helper call' }
```

Simpler enforceable check:

```powershell
if ($plan -notmatch 'Write-WinMintHostHeartbeat') { throw 'logged kernel must call Write-WinMintHostHeartbeat' }
$kernelFn = [regex]::Match($plan, '(?ms)^function Invoke-WinMintLoggedKernel \{.*?^\}').Value
if ($kernelFn -match 'Write-Host \$text\r?\n\s*\$quiet\.Restart' -and $kernelFn -match 'Opcode running') {
    throw 'logged kernel still Write-Host heartbeats'
}
```

Prefer: after extract, assert the quiet-timeout block contains `Write-WinMintHostHeartbeat` and does not contain `Write-Host $text` on the heartbeat branch:

```powershell
if ($kernelFn -notmatch 'Write-WinMintHostHeartbeat -Opcode') { throw 'heartbeat helper not called with -Opcode' }
if ($kernelFn -match '\$text = \"\$Opcode running[\s\S]{0,80}Write-Host \$text') {
    throw 'heartbeat still Write-Host'
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `pwsh -NoProfile -File tests/contract/Test-WinMintHostProgress.ps1`

- [ ] **Step 3: Change quiet branch in `Invoke-WinMintLoggedKernel`**

Replace:

```powershell
if ($quiet.Elapsed.TotalSeconds -ge $QuietSeconds) {
    $text = "$Opcode running $([int]$phase.Elapsed.TotalSeconds)s"
    $writer.WriteLine($text)
    Write-Host $text
    $quiet.Restart()
}
```

with:

```powershell
if ($quiet.Elapsed.TotalSeconds -ge $QuietSeconds) {
    Write-WinMintHostHeartbeat -Opcode $Opcode -ElapsedSeconds ([int]$phase.Elapsed.TotalSeconds) -LogWriter $writer
    $quiet.Restart()
}
```

Keep tee of kernel output:

```powershell
foreach ($item in @($out.ReadAll())) {
    $text = [string]$item
    $writer.WriteLine($text)
    Write-Host $text
    $quiet.Restart()
}
```

Ensure `Invoke-ServicingPlan.ps1` dots the helper before first use:

```powershell
. (Join-Path $PSScriptRoot '..\tools\host\Write-WinMintHostProgress.ps1')
```

(only if not already present).

- [ ] **Step 4: Run behavioural kernel probe in contract**

Existing extract + `Invoke-WinMintLoggedKernel` probe must still find `ProbeOp running` in the log file.

Run: `pwsh -NoProfile -File tests/contract/Test-WinMintHostProgress.ps1`

Expected: PASS.

- [ ] **Step 5: Commit (only if human asked)**

```text
feat(servicing): console progress for logged-kernel heartbeats
```

---

### Task 3: Quality hash / BITS / expand console progress

**Files:**
- Modify: `servicing/Add-QualityUpdates.ps1` (`Get-WinMintHeartbeatSha256`)
- Modify: `servicing/Resolve-WinMintQualityUpdate.ps1` (BITS wait loop, DISM expand wait)
- Modify: `tests/contract/Test-WinMintHostProgress.ps1` (keep milestone string contracts)

**Interfaces:**
- Consumes: `Write-WinMintHostProgress`, `Write-WinMintHostPhase` (dot helper from quality scripts or rely on logged-kernel tee only)
- Produces: unchanged milestone substrings required by contract: `quality package-set start`, `Catalog BITS start`, `quality hash start`, `quality expand start`, `quality packages apply`

**Dot-source:** At top of `Add-QualityUpdates.ps1` and once in `Resolve-WinMintQualityUpdate.ps1` (if not already):

```powershell
. (Join-Path $PSScriptRoot '..\tools\host\Write-WinMintHostProgress.ps1')
```

- [ ] **Step 1: Hash loop — console progress, trail sparse**

In `Get-WinMintHeartbeatSha256`, keep writing percent lines that the logged-kernel tee captures (trail), but drive console with progress. Minimal change that matches the spec:

```powershell
Write-Output ("quality hash 0% 0/{0:n0} MB" -f ($total / 1MB))
Write-WinMintHostProgress -Activity 'quality hash' -Status ("0/{0:n0} MB" -f ($total / 1MB)) -PercentComplete 0
# inside mark:
Write-Output ("quality hash {0}% {1:n0}/{2:n0} MB" -f $pct, ($done / 1MB), ($total / 1MB))
Write-WinMintHostProgress -Activity 'quality hash' -Status ("{0:n0}/{1:n0} MB" -f ($done / 1MB), ($total / 1MB)) -PercentComplete ([int]$pct)
# after hash:
Write-WinMintHostProgress -Activity 'quality hash' -Completed
```

Replace the previous `Write-Host` percent lines with `Write-Output` (trail via tee) + `Write-WinMintHostProgress` (console). Do **not** remove milestone `Write-Output "quality hash start …"` outside the function.

- [ ] **Step 2: BITS wait — progress status, rate-limited trail**

In the BITS wait loop, replace every-15s `Write-Host "quality BITS $state …"` with:

```powershell
$status = "quality BITS $state ${mb}MB $leaf ($([int]$wait.Elapsed.TotalSeconds)s)"
Write-WinMintHostProgress -Activity 'Catalog BITS' -Status $status
# trail every 60s or on state change (keep a $lastTrailState / Stopwatch):
if ($state -ne $lastTrailState -or $trailBeat.Elapsed.TotalSeconds -ge 60) {
    Write-Output $status
    $lastTrailState = $state
    $trailBeat.Restart()
}
```

Keep `Write-Host`/`Write-Output` for `quality BITS start` and `quality BITS ok` as milestones (prefer `Write-Output` so tee + success stream stay consistent; contract keys off `Catalog BITS start` from `Add-QualityUpdates.ps1`, not these host lines).

- [ ] **Step 3: Expand DISM wait**

Replace:

```powershell
Write-Host ("quality expand DISM running {0} ({1:n0}s)" -f $leaf, $wait.Elapsed.TotalSeconds)
```

with:

```powershell
Write-WinMintHostHeartbeat -Opcode 'quality expand DISM' -ElapsedSeconds ([int]$wait.Elapsed.TotalSeconds) -Activity 'quality expand'
```

For expand, there is no `LogWriter` in that function — heartbeat without `-LogWriter` still updates progress; emit trail via `Write-Output` only every other wait or rely on parent logged-kernel silence heartbeat. Spec: expand running ticks should not spam host. So:

```powershell
Write-WinMintHostProgress -Activity 'quality expand' -Status ("DISM $leaf $([int]$wait.Elapsed.TotalSeconds)s")
```

Keep start/ok as `Write-Output` (or Host once).

- [ ] **Step 4: Run contracts**

```powershell
pwsh -NoProfile -File tests/contract/Test-WinMintHostProgress.ps1
pwsh -NoProfile -File tests/contract/Test-QualityCatalog.ps1
```

Expected: PASS.

- [ ] **Step 5: Commit (only if human asked)**

```text
feat(servicing): progress bar for quality hash BITS expand waits
```

---

### Task 4: Watch filtered tail + format clarity

**Files:**
- Modify: `tools/host/Watch-Host.ps1`
- Modify: `tools/host/Write-WinMintHostProgress.ps1` (`Format-WinMintHostWatch` labels if needed)
- Modify: `tests/contract/Test-WinMintHostProgress.ps1`

**Interfaces:**
- Consumes: `Select-WinMintWatchLogTail`, `Read-WinMintApplyStatus`, `Format-WinMintHostWatch`
- Produces: Watch display omits heartbeat lines

- [ ] **Step 1: Contract for filtered dashboard tail**

```powershell
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
```

- [ ] **Step 2: Run — FAIL until Watch-Host wires filter**

- [ ] **Step 3: Wire `Watch-Host.ps1`**

Replace:

```powershell
$logTail = @(Get-Content -LiteralPath $snap.Log -Tail 8)
```

with:

```powershell
$rawTail = @(Get-Content -LiteralPath $snap.Log -Tail 40)
$logTail = @(Select-WinMintWatchLogTail -Lines $rawTail -Count 8)
```

Optional format tweak in `Format-WinMintHostWatch`: keep key columns; ensure `apply` / `stall` / `wall` labels stay aligned (no Get-Date).

- [ ] **Step 4: Run**

`pwsh -NoProfile -File tests/contract/Test-WinMintHostProgress.ps1`  
`pwsh -NoProfile -File tests/contract/Test-SmokeStatus.ps1`  
`pwsh -NoProfile -File tests/contract/Test-CheckStatus.ps1`

Expected: PASS.

- [ ] **Step 5: Commit (only if human asked)**

```text
feat(host): filter heartbeat noise from Watch log tail
```

---

### Task 5: Windows Terminal spawn + PID marker

**Files:**
- Modify: `tools/host/Write-WinMintHostProgress.ps1` (add `Start-WinMintHostWatchProcess`, `Resolve-WinMintWindowsTerminal`)
- Modify: `tools/host/Watch-Host.ps1` (param `-MarkerPath`, self-stamp `$PID`)
- Modify: `tools/vm/Invoke-Smoke.ps1` (use spawn helper)
- Modify: `tests/contract/Test-WinMintHostProgress.ps1`
- Modify: `tests/contract/Test-SmokeStatus.ps1` if spawn snippet assertions need updating

**Interfaces:**
- Consumes: `Get-SmokeWatcherSpawnDecision` (unchanged)
- Produces:
  - `Resolve-WinMintWindowsTerminal` → `[string]` path or empty
  - `Start-WinMintHostWatchProcess -RepoRoot -Work -Kind -PriorRunId -MarkerPath -PwshExe` → starts process; marker written by Watch-Host

- [ ] **Step 1: Contract assertions**

```powershell
if ($helper -notmatch 'function Start-WinMintHostWatchProcess') { throw 'helper must spawn watch via Start-WinMintHostWatchProcess' }
if ($helper -notmatch 'wt' -and $helper -notmatch 'WindowsTerminal') { throw 'spawn helper must consider wt.exe' }
if ($smoke -notmatch 'Start-WinMintHostWatchProcess') { throw 'Invoke-Smoke must use Start-WinMintHostWatchProcess' }
if ($watchHost -notmatch 'MarkerPath') { throw 'Watch-Host must accept -MarkerPath and self-stamp PID' }
```

- [ ] **Step 2: Implement resolve + spawn**

```powershell
function Resolve-WinMintWindowsTerminal {
    $cmd = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return [string]$cmd.Source }
    foreach ($candidate in @(
            (Join-Path $env:LocalAppData 'Microsoft\WindowsApps\wt.exe'),
            (Join-Path $env:ProgramFiles 'Windows Terminal\wt.exe')
        )) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return ''
}

function Start-WinMintHostWatchProcess {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $Work,
        [Parameter(Mandatory)] [ValidateSet('smoke', 'check', 'apply')] [string] $Kind,
        [string] $PriorRunId = '',
        [Parameter(Mandatory)] [string] $MarkerPath,
        [Parameter(Mandatory)] [string] $PwshExe
    )
    $watchScript = Join-Path $RepoRoot 'tools/host/Watch-Host.ps1'
    $title = "WinMint host watch — $Work"
    $pwshArgs = @(
        '-NoProfile', '-NonInteractive', '-File', $watchScript,
        '-Kind', $Kind, '-Work', $Work, '-MarkerPath', $MarkerPath
    )
    if ($PSBoundParameters.ContainsKey('PriorRunId')) {
        $pwshArgs += @('-PriorRunId', $PriorRunId)
    }
    $wt = Resolve-WinMintWindowsTerminal
    if ($wt) {
        # wt: new-tab with title + starting directory; commandline is pwsh …
        $wtArgs = @(
            'new-tab',
            '--title', $title,
            '-d', $RepoRoot,
            '--',
            $PwshExe
        ) + $pwshArgs
        Start-Process -FilePath $wt -WorkingDirectory $RepoRoot -ArgumentList $wtArgs | Out-Null
        return
    }
    $proc = Start-Process -FilePath $PwshExe -WorkingDirectory $RepoRoot -PassThru -ArgumentList $pwshArgs
    Set-Content -LiteralPath $MarkerPath -Value $proc.Id -Encoding utf8
}
```

When `wt` is used, do **not** trust wt’s PID as the watcher — Watch-Host stamps the marker.

- [ ] **Step 3: Watch-Host self-stamp**

Add param:

```powershell
[string] $MarkerPath = ''
```

Near top after title set:

```powershell
if (-not [string]::IsNullOrWhiteSpace($MarkerPath)) {
    Set-Content -LiteralPath $MarkerPath -Value $PID -Encoding utf8
}
```

- [ ] **Step 4: Invoke-Smoke call site**

Replace the `Start-Process -FilePath $pwshExe … Watch-Host` block with:

```powershell
Start-WinMintHostWatchProcess -RepoRoot $repoRoot -Work $workFull -Kind smoke `
    -PriorRunId '' -MarkerPath $watcherMarker -PwshExe $pwshExe
```

Ensure `Invoke-Smoke.ps1` already dots `Write-WinMintHostProgress.ps1` (it does).

For empty PriorRunId, preserve today’s `-PriorRunId:` binding semantics (leftover/empty). Pass `-PriorRunId ''` and in Watch-Host keep `ContainsKey` behaviour — Smoke today uses `-PriorRunId:` switch-style empty. Match existing: ArgumentList `'-PriorRunId:'` if that is what contracts require.

Contract today:

```powershell
if ($spawn -match '\$runId') { throw '…' }
if ($spawn -notmatch 'PriorRunId') { throw '…' }
```

Keep passing `-PriorRunId:` as an argument element when kind is smoke so leftover/empty semantics remain.

- [ ] **Step 5: Run**

```powershell
pwsh -NoProfile -File tests/contract/Test-WinMintHostProgress.ps1
pwsh -NoProfile -File tests/contract/Test-SmokeStatus.ps1
```

Expected: PASS.

- [ ] **Step 6: Commit (only if human asked)**

```text
feat(host): spawn Watch-Host via Windows Terminal when available
```

---

### Task 6: Host Apply / Smoke copy pass

**Files:**
- Modify: `tools/apply/Invoke-HostApply.ps1` (banner `Write-Host` lines ~174–247)
- Modify: `tools/vm/Invoke-Smoke.ps1` only if any remaining raw Apply banners bypass `Write-SmokeHostLine`

**Interfaces:**
- Consumes: `Write-WinMintHostPhase`
- Produces: same operator facts (Profile, Iso, Work, lane, Output ISO path); clearer lane-colored lines

- [ ] **Step 1: Dot helper in Host Apply if missing**

```powershell
. (Join-Path $repoRoot 'tools/host/Write-WinMintHostProgress.ps1')
```

- [ ] **Step 2: Replace key banners**

Example:

```powershell
Write-WinMintHostPhase -Lane Apply -Name "Profile=$Profile Iso=$Iso Work=$Work Lane=$ImageQuality"
Write-WinMintHostPhase -Lane Apply -Name 'Pre-wipe only: mutates offline WIM from Source ISO — does not install to this device.'
```

Keep failure/flash warnings as phase lines with `-Outcome failed` only for true failures; warnings stay Host/Yellow via phase Name text (no new color API).

- [ ] **Step 3: Run**

```powershell
pwsh -NoProfile -File tests/contract/Test-WinMintHostProgress.ps1
pwsh -NoProfile -File tests/contract/Test-ApplyEvidence.ps1
```

Expected: PASS (evidence contracts must not depend on exact Host Apply banner strings — if they do, keep those strings verbatim).

- [ ] **Step 4: Commit (only if human asked)**

```text
feat(apply): route Host Apply banners through host phase helper
```

---

### Task 7: Full gate

**Files:** none (verification only)

- [ ] **Step 1: Run `just check`**

```powershell
just check
```

Expected: exit 0.

- [ ] **Step 2: Manual smoke glance (human)**

When convenient: elevated Smoke or Host Apply in Windows Terminal — confirm no scrolling `running Ns` host spam; Watch opens in WT; stage log still grows heartbeats.

- [ ] **Step 3: Commit docs if not already (only if human asked)**

```text
docs: host console UX design and implementation plan
```

---

## Spec coverage check

| Spec requirement | Task |
|------------------|------|
| Trail vs console split | 1–2 |
| `Write-Progress` Minimal + OSC when interactive VT | 1 |
| Heartbeat helper, no host spam | 1–2 |
| Quality hash/BITS/expand console progress | 3 |
| Watch filtered tail | 4 |
| `wt` spawn + PID self-stamp | 5 |
| Host Apply / Smoke copy | 6 |
| Wizard UI out of scope / apply-status keys unchanged | constraints + no task |
| `just check` green | 7 |

## Placeholder scan

None intentional. Expand DISM uses progress status without inventing package %.

## Type / name consistency

- `Write-WinMintHostHeartbeat -Opcode -ElapsedSeconds [-LogWriter] [-Activity]`
- `Test-WinMintTrailHeartbeatLine -Line`
- `Select-WinMintWatchLogTail -Lines -Count`
- `Start-WinMintHostWatchProcess -RepoRoot -Work -Kind -PriorRunId -MarkerPath -PwshExe`
- `Resolve-WinMintWindowsTerminal` → path or `''`
