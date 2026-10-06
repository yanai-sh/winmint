# Smoke S4 acceptance facts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Smoke/Test-lane FirstLogon phase vocabulary and chrome literals out of `Assert-SmokeEvidence` into a PS facts module; Assert evaluates that fact set. Handoff readiness stays unlock-only.

**Architecture:** Mirror #145’s *evaluate-only assert + named fact helper* pattern in PowerShell only — do **not** freeze S4 facts on `expected-evidence.json` or touch `HostReview`. Product constants live in `Get-WinMintSmokeS4AcceptanceFacts`; Assert applies them and keeps Profile pin parameters on its own surface.

**Tech Stack:** PowerShell 7.6+, contract fixtures (`tests/contract/Test-SmokeEvidence.ps1`), no Hyper-V to close.

## Global Constraints

- Spec: GitHub issue #152
- `Get-WinMintGuestHandoffReadiness` unchanged (do not fold phase/chrome lists into handoff)
- Profile pin parameters stay on Assert (`PinnedRemoveAppx`, `PinnedOnlineRemoveAppx`, `PinnedRemoveCapabilities`, `PinnedDisableOptionalFeatures`, `ExpectNativePackageAudit`)
- Facts own product-constant vocabulary (required phases, DMA/setup-region alternatives, wallpaper path, baseline pins, quiet DWords, package-strict pin map)
- Contract fixtures only — no Hyper-V / live Smoke to close
- Orthogonal to wipe-ready Gate B expected-evidence (#145 done)
- Out of scope: #120 maintainer live Smoke · Primary · renaming Supervisor phase product strings beyond centralizing Assert’s list · C# Smoke acceptance type
- Ponytail: one facts module + Assert evaluate; no second planner, no schema bump, no CONTEXT/ADR edits
- Commit style: `docs:` · `feat(scope):` · `fix(scope):` …
- Focused contract while iterating; `just check` before final task commit
- Work on branch `sdd/152-smoke-s4-facts`; commit when a task’s Commit step says so
- After land: close #152 with summary; leave #120/#96 alone

## File map

| File | Responsibility |
|------|----------------|
| `tools/vm/SmokeS4AcceptanceFacts.ps1` | `Get-WinMintSmokeS4AcceptanceFacts` — product-constant phases + chrome predicates |
| `tools/vm/Assert-SmokeEvidence.ps1` | Dot facts; evaluate-only for phases/chrome; keep pins + handoff + apply digests |
| `tools/vm/SmokeStatus.ps1` | **Unchanged** handoff |
| `tests/contract/Test-SmokeEvidence.ps1` | Fixture missing a required phase fails via facts; Assert dots facts module |
| `tests/fixtures/smoke-evidence/` | Unchanged green fixture (must still pass) |

---

### Task 1: Facts module + failing contract for missing required phase

**Files:**
- Create: `tools/vm/SmokeS4AcceptanceFacts.ps1`
- Modify: `tests/contract/Test-SmokeEvidence.ps1`
- Keep: fixture tree green path

**Interfaces:**
- Produces: `Get-WinMintSmokeS4AcceptanceFacts` → `[pscustomobject]` with at least:
  - `RequiredPhases` — `[string[]]` absolute required phase tokens (today: `shell.firstPaint`, `jobs.workstation.quiet`, `jobs.wsl.platform.mocked`, `shell.chrome`)
  - `SplashBeforeSettle` — order rule: if `settle.begin` present, `shell.firstPaint` index must be less than `settle.begin` index
  - `DmaOkAnyOf` — alternatives: `settle.ok` \| `settle.locationWarn` \| (`settle.resumeOk` ∧ `checkpoint.resume`)
  - `SetupRegionOkAnyOf` — `settle.deviceRegionOk` \| `settle.deviceRegionRepaired`
  - `OnlineRemoveSafetyNet` — if any `removed.appx.online.*` then at least one `deprovisioned.appx.*`
  - `ExpectedWallpaperPath` — `C:\Windows\Web\Wallpaper\Windows\WinMint-Bloom.jpg`
  - `RequiredStartPinIds` — `explorer`, `settings`, `terminal`
  - `RequiredTaskbarPinIds` — `explorer`, `terminal`
  - `RequiredQuietDwords` — ordered hashtable of name→0 (SearchboxTaskbarMode, TaskbarDa, TaskbarMn, ShowTaskViewButton, ShowCopilotButton)
  - `PackageStrictExtraPins` — ordered map wingetId→pinId (`Anysphere.Cursor`→`cursor`, `Zen-Team.Zen-Browser`→`zen-browser`)
- Consumes: nothing (pure constants)

- [ ] **Step 1: Add contract cases** (before wiring Assert):

```powershell
# After existing green fixture pass:
$factsPath = Join-Path $repo 'tools\vm\SmokeS4AcceptanceFacts.ps1'
if (-not (Test-Path -LiteralPath $factsPath)) { throw 'SmokeS4AcceptanceFacts.ps1 missing' }
. $factsPath
$facts = Get-WinMintSmokeS4AcceptanceFacts
if ($facts.RequiredPhases -notcontains 'shell.firstPaint') { throw 'facts must list shell.firstPaint' }

$nofactsphase = Join-Path $root 'nofactsphase'
Copy-Tree $fixture $nofactsphase
Remove-Item -LiteralPath (Join-Path $nofactsphase 'acceptance.json') -ErrorAction SilentlyContinue
$guest = Get-Content -LiteralPath (Guest-EvidencePath $nofactsphase) -Raw | ConvertFrom-Json
# Drop a facts-owned required phase (keep handoff phases jobs.ok + oobe.dismiss so failure is facts, not handoff)
$guest.phases = @($guest.phases | Where-Object { $_ -cne 'jobs.workstation.quiet' })
($guest | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Guest-EvidencePath $nofactsphase) -Encoding utf8
$r = Invoke-StaticAssert $nofactsphase
if ($r.Code -eq 0) { throw 'missing facts-required phase must fail' }
if ($r.Err -notmatch 'jobs\.workstation\.quiet|quiet chrome') {
    throw "facts-phase message: $($r.Err)"
}

# Assert must dot the facts module (source text)
$assertSrc = Get-Content -LiteralPath $assert -Raw -Encoding utf8
if ($assertSrc -notmatch 'SmokeS4AcceptanceFacts\.ps1') {
    throw 'Assert-SmokeEvidence must dot SmokeS4AcceptanceFacts.ps1'
}
if ($assertSrc -notmatch 'Get-WinMintSmokeS4AcceptanceFacts') {
    throw 'Assert-SmokeEvidence must call Get-WinMintSmokeS4AcceptanceFacts'
}
```

- [ ] **Step 2: Run contract — expect FAIL** on missing facts module / Assert not dotted

```powershell
pwsh -NoProfile -File tests/contract/Test-SmokeEvidence.ps1
```

Expected: FAIL (facts file missing or Assert does not reference it)

- [ ] **Step 3: Implement `SmokeS4AcceptanceFacts.ps1`** with the interface above — copy current literals from Assert lines 77–121 and 228–297 into the returned object (no behavior change yet)

- [ ] **Step 4: Commit**

```
feat(smoke): S4 acceptance facts module (constants only)
```

---

### Task 2: Assert evaluate-only for phases/chrome + gate green

**Files:**
- Modify: `tools/vm/Assert-SmokeEvidence.ps1`
- Modify: `tests/contract/Test-SmokeEvidence.ps1` (if message text changes — keep match resilient)
- Keep: `SmokeStatus.ps1` handoff path identical

**Interfaces:**
- Consumes: `Get-WinMintSmokeS4AcceptanceFacts`
- Assert becomes: load facts once → foreach required phase throw if missing → evaluate splash-before-settle / DMA / setup-region / online safety-net from facts → evaluate chrome against facts → **unchanged** handoff call + pin digests + firstPaintMs + native audit switch
- Produces: same `winmint.smoke.acceptance/v1` on success

- [ ] **Step 1: Wire Assert**

Near top (after existing dots):

```powershell
. (Join-Path $PSScriptRoot 'SmokeS4AcceptanceFacts.ps1')
$s4Facts = Get-WinMintSmokeS4AcceptanceFacts
```

Replace hardcoded phase/chrome blocks with evaluation against `$s4Facts` (same throw messages preferred so contract regexes keep working; if a message must change, update the contract match in the same commit).

Do **not** move pin-parameter logic into facts. Do **not** change `Get-WinMintGuestHandoffReadiness` call.

- [ ] **Step 2: Run Smoke evidence contract — PASS**

```powershell
pwsh -NoProfile -File tests/contract/Test-SmokeEvidence.ps1
pwsh -NoProfile -File tests/contract/Test-SmokeStatus.ps1
```

Expected: PASS (handoff still shared; Assert dots facts)

- [ ] **Step 3: `just check` green**

- [ ] **Step 4: Commit**

```
refactor(smoke): Assert-SmokeEvidence evaluates S4 acceptance facts
```

- [ ] **Step 5: Close #152** with short summary (facts module path + evaluate-only Assert); do not close #120

---

## Self-review

1. Spec coverage: facts module · Assert evaluate-only · handoff unchanged · pins on Assert · fixture missing phase fails · `just check` — all tasked.
2. Placeholders: none.
3. Types: single `Get-WinMintSmokeS4AcceptanceFacts` name used in both tasks.
