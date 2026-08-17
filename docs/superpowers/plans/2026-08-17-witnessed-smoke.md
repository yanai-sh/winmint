# Witnessed Smoke status + `-Monitor` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a watch-only `smoke-status.json` projection and optional `-Monitor` (Hyper-V Connect) to S4, then the maintainer runs one current-HEAD Smoke with monitoring on.

**Architecture:** Extract host-only helpers into `tools/vm/SmokeStatus.ps1` so `just check` can call them without Hyper-V. `Invoke-Smoke.ps1` dotsources that file, writes `{Work}/smoke-status.json` at phase changes and each wait poll, and may start `vmconnect.exe` after `Start-VM`. The wait loop still decides the next phase from live VM/guest state — it must not read the status file.

**Tech Stack:** pwsh 7.6+, Hyper-V (`vmconnect.exe` opt-in), existing `tests/contract/Test-*.ps1` discovery, `just smoke`.

**Spec:** [2026-08-17-witnessed-smoke-design.md](../specs/2026-08-17-witnessed-smoke-design.md)  
**Issue:** [#120](https://github.com/yanai-sh/winmint/issues/120)

## Global Constraints

- pwsh 7.6+ (`#requires -Version 7.6`).
- `just check` stays free of Hyper-V and of a Source ISO.
- One Apply per Host; mutex `Global\WinMint.ImageServicing.v1`; do not start a second Smoke.
- Status path is `{Work}/smoke-status.json` — not under `smoke-evidence/`, not Evidence, not a control plane.
- Schema `winmint.smoke.status/v1`. Phases: `apply` | `vm-boot` | `winpe-apply` | `setup-reboot` | `guest-up` | `assert` | `green` | `failed`. Never `splash` or `firstlogon`.
- Status write failure → `Write-Warning`, do not fail Smoke.
- `-Monitor` default off; missing/unstartable `vmconnect` → `Write-Warning`, continue.
- Default wall stays 90 minutes. Prove-out passes 180 only.
- Do not spawn a sidecar to scrape DISM. During blocking Apply, status stays `phase=apply`; DISM stdout is the Apply feed.
- Do not change DESIGN’s Smoke assert bar. Do not implement S5, Primary, dashboards, or screenshots.

## File structure

| Path | Responsibility |
| --- | --- |
| Create `tools/vm/SmokeStatus.ps1` | `Resolve-SmokePhase`, `Write-SmokeStatus`, `Start-SmokeMonitor`. No Hyper-V cmdlets, no `param()` block. |
| Modify `tools/vm/Invoke-Smoke.ps1` | Dot-source helpers; `-Monitor`; write status; never `Get-Content` the status file to decide control flow. |
| Create `tests/contract/Test-SmokeStatus.ps1` | Phase map, status schema, monitor warn-on-missing. Discovered by `just contract-tests`. |
| Modify `Justfile` (`smoke` recipe) | Optional `WALL` (default `90`) and `MONITOR` (empty = omit `-Monitor`). |

---

### Task 1: `Resolve-SmokePhase`

**Files:**
- Create: `tools/vm/SmokeStatus.ps1`
- Create: `tests/contract/Test-SmokeStatus.ps1`

**Interfaces:**
- Consumes: nothing
- Produces: `Resolve-SmokePhase` with parameters `HostStage` (`apply`|`wait`|`assert`|`green`|`failed`), `VmState` (string or `$null`), `VhdFileSizeBytes` (`[long]`, default 0), `HeartbeatOk` (`[bool]`, default `$false`), `EvidenceReady` (`[bool]`, default `$false`). Returns one of the spec phase strings. Priority when `HostStage=wait`: not-Running → `setup-reboot`; heartbeat OK → `guest-up`; VHD ≥ 1GB → `winpe-apply`; else `vm-boot`.

- [ ] **Step 1: Write the failing contract test**

Create `tests/contract/Test-SmokeStatus.ps1`:

```powershell
#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools/vm/SmokeStatus.ps1')

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

Write-Output 'Test-SmokeStatus ok'
exit 0
```

- [ ] **Step 2: Run it to verify it fails**

```powershell
pwsh -NoProfile -File tests/contract/Test-SmokeStatus.ps1
```

Expected: FAIL — `tools/vm/SmokeStatus.ps1` missing or `Resolve-SmokePhase` not found.

- [ ] **Step 3: Minimal `Resolve-SmokePhase`**

Create `tools/vm/SmokeStatus.ps1`:

```powershell
#requires -Version 7.6
Set-StrictMode -Version Latest

function Resolve-SmokePhase {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('apply', 'wait', 'assert', 'green', 'failed')]
        [string] $HostStage,
        [string] $VmState,
        [long] $VhdFileSizeBytes = 0,
        [switch] $HeartbeatOk,
        [switch] $EvidenceReady
    )
    switch ($HostStage) {
        'apply' { return 'apply' }
        'assert' { return 'assert' }
        'green' { return 'green' }
        'failed' { return 'failed' }
    }
    if ($VmState -notin @('Running')) { return 'setup-reboot' }
    if ($HeartbeatOk) { return 'guest-up' }
    if ($VhdFileSizeBytes -ge 1GB) { return 'winpe-apply' }
    return 'vm-boot'
}
```

`$EvidenceReady` is unused on purpose (HostStage flips to `assert` after pull). Keep the parameter so the wait loop can pass it without a second function.

- [ ] **Step 4: Re-run the test**

```powershell
pwsh -NoProfile -File tests/contract/Test-SmokeStatus.ps1
```

Expected: `Test-SmokeStatus ok`, exit 0.

- [ ] **Step 5: Commit**

```powershell
git add tools/vm/SmokeStatus.ps1 tests/contract/Test-SmokeStatus.ps1
git commit -m "feat(smoke): map host VM snapshots to Smoke status phases"
```

---

### Task 2: `Write-SmokeStatus`

**Files:**
- Modify: `tools/vm/SmokeStatus.ps1`
- Modify: `tests/contract/Test-SmokeStatus.ps1`

**Interfaces:**
- Consumes: `Resolve-SmokePhase` from Task 1
- Produces: `Write-SmokeStatus -Path <string>` plus the spec fields (`Phase`, `VmName`, `VmState`, `Cpu`, `Heartbeat`, `VhdFileSizeMB`, `StallMinutesLeft`, `WallMinutesLeft`, `LastHostLine`, `OutputIso`). Writes `schemaVersion=winmint.smoke.status/v1` and UTC `updatedAt`. Nulls allowed for VM fields during `apply`. Create parent directory. Catch write failures → `Write-Warning`, do not throw.

- [ ] **Step 1: Extend the contract test (append before the final `Write-Output`)**

```powershell
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

    $blocked = Join-Path $tmp 'blocked'
    Set-Content -LiteralPath $blocked -Value 'not-a-dir' -Encoding utf8
    Write-SmokeStatus -Path (Join-Path $blocked 'smoke-status.json') -Phase failed `
        -VmName 'winmint-smoke' -StallMinutesLeft 0 -WallMinutesLeft 0 -LastHostLine 'fail'
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
```

The blocked-path call must not throw (warning only).

- [ ] **Step 2: Run to verify fail**

```powershell
pwsh -NoProfile -File tests/contract/Test-SmokeStatus.ps1
```

Expected: FAIL — `Write-SmokeStatus` not found.

- [ ] **Step 3: Add `Write-SmokeStatus` to `tools/vm/SmokeStatus.ps1`**

```powershell
function Write-SmokeStatus {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Phase,
        [Parameter(Mandatory)][string] $VmName,
        $VmState = $null,
        $Cpu = $null,
        $Heartbeat = $null,
        $VhdFileSizeMB = $null,
        [int] $StallMinutesLeft = 0,
        [int] $WallMinutesLeft = 0,
        [string] $LastHostLine = '',
        $OutputIso = $null
    )
    try {
        $dir = Split-Path -Parent $Path
        if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $doc = [ordered]@{
            schemaVersion    = 'winmint.smoke.status/v1'
            updatedAt        = [datetime]::UtcNow.ToString('o')
            phase            = $Phase
            vmName           = $VmName
            vmState          = $VmState
            cpu              = $Cpu
            heartbeat        = $Heartbeat
            vhdFileSizeMB    = $VhdFileSizeMB
            stallMinutesLeft = $StallMinutesLeft
            wallMinutesLeft  = $WallMinutesLeft
            lastHostLine     = $LastHostLine
            outputIso        = $OutputIso
        }
        ($doc | ConvertTo-Json -Compress) | Set-Content -LiteralPath $Path -Encoding utf8
    }
    catch {
        Write-Warning "Could not write Smoke status: $($_.Exception.Message)"
    }
}
```

- [ ] **Step 4: Re-run the test**

```powershell
pwsh -NoProfile -File tests/contract/Test-SmokeStatus.ps1
```

Expected: `Test-SmokeStatus ok`, exit 0.

- [ ] **Step 5: Commit**

```powershell
git add tools/vm/SmokeStatus.ps1 tests/contract/Test-SmokeStatus.ps1
git commit -m "feat(smoke): write watch-only smoke-status.json"
```

---

### Task 3: `Start-SmokeMonitor`

**Files:**
- Modify: `tools/vm/SmokeStatus.ps1`
- Modify: `tests/contract/Test-SmokeStatus.ps1`

**Interfaces:**
- Consumes: nothing from the wait loop
- Produces: `Start-SmokeMonitor -VmName <string> [-ConnectExe <string>] [-Launcher <scriptblock>]`. Default `ConnectExe` = `Join-Path $env:WINDIR 'System32\vmconnect.exe'`. Default `Launcher` = `{ param($Exe, $VmName) Start-Process -FilePath $Exe -ArgumentList @('localhost', $VmName) }`. If `ConnectExe` is missing, `Write-Warning` and return. If `Launcher` throws, `Write-Warning` and return. Never throw.

- [ ] **Step 1: Extend the contract test**

```powershell
Start-SmokeMonitor -VmName 'winmint-smoke' -ConnectExe 'C:\no-such-vmconnect.exe'
$script:launched = $null
Start-SmokeMonitor -VmName 'winmint-smoke' -ConnectExe $PSCommandPath -Launcher {
    param($Exe, $VmName)
    $script:launched = @{ Exe = $Exe; VmName = $VmName }
}
if ($null -eq $script:launched) { throw 'Launcher not called for existing ConnectExe' }
Assert-Eq $script:launched.VmName 'winmint-smoke' 'vmconnect vm name'
Start-SmokeMonitor -VmName 'x' -ConnectExe $PSCommandPath -Launcher { throw 'boom' }
```

Missing exe and throwing launcher must not throw out of `Start-SmokeMonitor`.

- [ ] **Step 2: Run to verify fail**

```powershell
pwsh -NoProfile -File tests/contract/Test-SmokeStatus.ps1
```

Expected: FAIL — `Start-SmokeMonitor` not found.

- [ ] **Step 3: Add `Start-SmokeMonitor`**

```powershell
function Start-SmokeMonitor {
    param(
        [Parameter(Mandatory)][string] $VmName,
        [string] $ConnectExe = (Join-Path $env:WINDIR 'System32\vmconnect.exe'),
        [scriptblock] $Launcher = {
            param($Exe, $Name)
            Start-Process -FilePath $Exe -ArgumentList @('localhost', $Name)
        }
    )
    if (-not (Test-Path -LiteralPath $ConnectExe)) {
        Write-Warning "vmconnect.exe not found; continuing headless"
        return
    }
    try {
        & $Launcher $ConnectExe $VmName
    }
    catch {
        Write-Warning "Could not start VMConnect: $($_.Exception.Message)"
    }
}
```

- [ ] **Step 4: Re-run the test**

```powershell
pwsh -NoProfile -File tests/contract/Test-SmokeStatus.ps1
```

Expected: `Test-SmokeStatus ok`, exit 0.

- [ ] **Step 5: Commit**

```powershell
git add tools/vm/SmokeStatus.ps1 tests/contract/Test-SmokeStatus.ps1
git commit -m "feat(smoke): optional VMConnect monitor that cannot fail Smoke"
```

---

### Task 4: Wire `Invoke-Smoke.ps1` and `just smoke`

**Files:**
- Modify: `tools/vm/Invoke-Smoke.ps1` (param block ~18–49; after `$repoRoot`; Apply start ~90; after `Start-VM` ~184; wait loop ~427–475; assert ~481–488)
- Modify: `Justfile` lines 98–100
- Modify: `tests/contract/Test-SmokeStatus.ps1` (source-contract that Invoke-Smoke dotsources and does not read the status file for control)

**Interfaces:**
- Consumes: `Resolve-SmokePhase`, `Write-SmokeStatus`, `Start-SmokeMonitor`
- Produces: `-Monitor` switch on parameter set `Run`; `$statusPath = Join-Path $Work 'smoke-status.json'`; Justfile `WALL` default `90`, `MONITOR` empty omits `-Monitor`

- [ ] **Step 1: Add source-contract asserts to `Test-SmokeStatus.ps1`**

```powershell
$smoke = Get-Content -LiteralPath (Join-Path $repo 'tools/vm/Invoke-Smoke.ps1') -Raw -Encoding utf8
if ($smoke -notmatch 'tools[/\\]vm[/\\]SmokeStatus\.ps1') { throw 'Invoke-Smoke must dot-source SmokeStatus.ps1' }
if ($smoke -notmatch '\[switch\]\s*\$Monitor') { throw '-Monitor switch missing' }
if ($smoke -notmatch 'Start-SmokeMonitor') { throw 'Start-SmokeMonitor not called' }
if ($smoke -notmatch 'Write-SmokeStatus') { throw 'Write-SmokeStatus not called' }
if ($smoke -match 'Get-Content[^\n]*smoke-status\.json') { throw 'must not read smoke-status.json as control plane' }
```

- [ ] **Step 2: Run to verify fail**

```powershell
pwsh -NoProfile -File tests/contract/Test-SmokeStatus.ps1
```

Expected: FAIL on missing dot-source / `-Monitor`.

- [ ] **Step 3: Wire the harness**

In `Invoke-Smoke.ps1` param set `Run`, add:

```powershell
[Parameter(ParameterSetName = 'Run')]
[switch] $Monitor
```

After `$repoRoot = Resolve-Path ...` (and `Set-Location`), before Apply:

```powershell
. (Join-Path $PSScriptRoot 'SmokeStatus.ps1')
$statusPath = Join-Path $Work 'smoke-status.json'
```

Do **not** dot-source inside `-AssertOnly` before exit if that path never waits — still fine to dot-source once at the top after `$repoRoot` for both sets (AssertOnly ignores status).

Immediately before the Apply call (the existing `Applying Profile=` `Write-Host`), and after a successful Apply when `$outIso` is known:

```powershell
Write-SmokeStatus -Path $statusPath -Phase (Resolve-SmokePhase -HostStage apply) `
    -VmName $VmName -StallMinutesLeft $StallMinutes -WallMinutesLeft $WallClockMinutes `
    -LastHostLine "Applying Profile=$Profile" -OutputIso $null
```

After `Start-VM` (the existing `VM ready.` line):

```powershell
if ($Monitor) { Start-SmokeMonitor -VmName $VmName }
```

Inside the wait `while` loop, after `$vm = Get-VM ...` and the existing state `switch`, compute VHD size / heartbeat with the existing `Test-SmokeVhdHasImage` / `Test-GuestWindowsHeartbeat`, then:

```powershell
$vhdBytes = 0
try {
    $drive = Get-VMHardDiskDrive -VMName $VmName | Select-Object -First 1
    if ($drive) { $vhdBytes = [long](Get-VHD -Path $drive.Path).FileSize }
} catch { $vhdBytes = 0 }
$hb = Test-GuestWindowsHeartbeat
$phase = Resolve-SmokePhase -HostStage wait -VmState ([string]$vm.State) `
    -VhdFileSizeBytes $vhdBytes -HeartbeatOk:$hb
$stallLeft = [math]::Max(0, [int]($stallDeadline - [datetime]::UtcNow).TotalMinutes)
$wallLeft = [math]::Max(0, [int]($deadline - [datetime]::UtcNow).TotalMinutes)
Write-SmokeStatus -Path $statusPath -Phase $phase -VmName $VmName -VmState ([string]$vm.State) `
    -Cpu $cpu -Heartbeat $(if ($hb) { 'OK' } else { 'No Contact' }) `
    -VhdFileSizeMB ([int][math]::Round($vhdBytes / 1MB)) `
    -StallMinutesLeft $stallLeft -WallMinutesLeft $wallLeft `
    -LastHostLine "VM $([string]$vm.State)" -OutputIso $outIso
```

`$outIso` is already resolved in this script (see `Resolve-OutputIso.ps1`). Use that variable; do not re-hash.

Wrap the wait + assert in try/catch so failures still write `failed`:

```powershell
try {
    # existing while loop …
    Write-SmokeStatus -Path $statusPath -Phase (Resolve-SmokePhase -HostStage assert) `
        -VmName $VmName -StallMinutesLeft 0 -WallMinutesLeft $wallLeft `
        -LastHostLine 'Guest evidence pulled.' -OutputIso $outIso
    & $assertScript ...
    if ($LASTEXITCODE -ne 0) { throw "Assert-SmokeEvidence exit $LASTEXITCODE" }
    Write-SmokeStatus -Path $statusPath -Phase (Resolve-SmokePhase -HostStage green) `
        -VmName $VmName -LastHostLine 'Smoke green' -OutputIso $outIso
    Write-Host "Smoke green. Evidence: $evidenceOut"
    exit 0
}
catch {
    Write-SmokeStatus -Path $statusPath -Phase (Resolve-SmokePhase -HostStage failed) `
        -VmName $VmName -LastHostLine ([string]$_.Exception.Message) -OutputIso $outIso
    throw
}
```

Keep stall `throw "STALL_SUSPECT:…"` inside that try so it records `failed`.

Replace the `Justfile` `smoke` recipe (windows-shell is already pwsh):

```
smoke ISO WORK=".scratch/smoke" PROFILE="samples/acceptance.profile.json" WALL="90" MONITOR="":
    $mon = @(); if ('{{MONITOR}}') { $mon = @('-Monitor') }; pwsh -NoProfile -File '{{justfile_directory()}}/tools/vm/Invoke-Smoke.ps1' -Iso '{{ISO}}' -Work '{{WORK}}' -Profile '{{PROFILE}}' -WallClockMinutes {{WALL}} @mon
```

- [ ] **Step 4: Run contract tests**

```powershell
pwsh -NoProfile -File tests/contract/Test-SmokeStatus.ps1
pwsh -NoProfile -File tests/contract/Test-SmokeDiskBoot.ps1
just contract-tests
```

Expected: all exit 0. `Test-SmokeDiskBoot` still passes (Prefer-DiskBoot / 8GB RAM unchanged).

- [ ] **Step 5: Commit**

```powershell
git add tools/vm/Invoke-Smoke.ps1 Justfile tests/contract/Test-SmokeStatus.ps1
git commit -m "feat(smoke): live smoke-status.json and optional -Monitor"
```

---

### Task 5: Maintainer prove-out (no code)

**Files:** none. Issue [#120](https://github.com/yanai-sh/winmint/issues/120).

**Interfaces:**
- Consumes: Task 4 harness on current `main`
- Produces: issue comment with HEAD, Output ISO leaf, gates seen, `Smoke green` or fail

- [ ] **Step 1: Label**

`ready-for-agent` off. `ready-for-human` on. Mutex free. No second Apply.

- [ ] **Step 2: Run (elevated MSI pwsh, no `-SkipApply`)**

```powershell
pwsh -NoProfile -File tools/vm/Invoke-Smoke.ps1 `
  -Iso 'C:\Users\yanai\AppData\Local\WinMint\source-iso\Win11_25H2_English_Arm64_v2.iso' `
  -Work '.scratch/smoke' `
  -Profile 'samples/acceptance.profile.json' `
  -WallClockMinutes 180 `
  -Monitor
```

Equivalent: `just smoke ISO='C:\Users\yanai\AppData\Local\WinMint\source-iso\Win11_25H2_English_Arm64_v2.iso' WALL=180 MONITOR=1`

- [ ] **Step 3: Watch Connect**

WinPE apply with no click. Splash then Explorer. AFK during hashing/export is fine. Clicking the guest fails this prove-out even if assert later passes.

- [ ] **Step 4: Comment on #120**

HEAD, Output ISO leaf, both gates y/n, `Smoke green` or the fail line, path to `.scratch/smoke/smoke-evidence/acceptance.json`. Optional: `{Work}/smoke-status.json` ended `phase=green`.

- [ ] **Step 5: Stop**

Do not start Primary (#96). A fail is a new issue, not more slices on this plan.

---

## Self-review

| Spec requirement | Task |
| --- | --- |
| One elevated S4 command, no guest click | existing harness + Task 5 |
| `smoke-status.json` watch-only, not Evidence | Tasks 1–2, 4 |
| Phases including heartbeat-wins-VHD | Task 1 |
| Write failure is a warning | Task 2 |
| `-Monitor` after Start-VM; missing vmconnect cannot fail | Task 3–4 |
| Justfile `WALL` / `MONITOR` | Task 4 |
| `just check` / contract, no Hyper-V | Tasks 1–4 |
| Prove-out 180 + acceptance Profile + no SkipApply | Task 5 |
| Do not read status as control plane | Task 4 source-contract |
| No DISM sidecar | Task 4 (no new process during Apply) |
