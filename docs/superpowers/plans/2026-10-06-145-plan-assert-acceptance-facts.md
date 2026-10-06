# #145 Plan↔assert acceptance facts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One wipe-ready Gate B claim across C# and harness asserts. Materialize freezes `packageWireHonest` on expected-evidence; PS wipe-ready mirrors `HostReview.IsGateB`. Lane∧strict input gate is renamed so Flash never reads the thinner predicate.

**Architecture:** Acceptance facts live on `expected-evidence.json` (already the assert seam). Add `packageWireHonest` from `BuildArtifacts.PackageWireHonest` on every write. PS `Test-/Assert-WinMintIsGateB` become wipe-ready (Release ∧ packageStrict ∧ packageWireHonest). Pre-Apply Release-without-strict stays `Test-/Assert-WinMintIsReleaseStrict`. No second planner.

**Tech Stack:** .NET 11 / C#, PowerShell asserts (`tools/host`, `tools/apply`), contract fixtures, xUnit expected-evidence tests.

## Global Constraints

- Spec: GitHub issue #145 (Part of #142). Map #142; #147 already landed (SoftwarePlan owns package facts).
- Wipe-ready = `HostReview.IsGateB` = Release ∧ package-strict ∧ package wire honest.
- Freeze `packageWireHonest` on every expected-evidence write (Test and Release). Schema stays `winmint.expected-evidence/v1`.
- Fail-closed: when asserting wipe-ready / when expected-evidence has `packageStrict` and Gate B path runs, missing `packageWireHonest` throws.
- Naming: wipe-ready owns `Test-WinMintIsGateB` / `Assert-WinMintGateB`. Lane∧strict → `Test-WinMintIsReleaseStrict` / `Assert-WinMintReleaseStrict`.
- Pre-Apply (`Invoke-HostApply` refuse soft Release): ReleaseStrict only. Post-Apply Flash guidance + evidence Gate B: wipe-ready from expected-evidence (not CLI `-PackageStrict` alone).
- Thin PS adapter OK; do not re-scrape `stages.json` for honesty.
- Update CONTEXT.md Gate B gloss + avoid-list (polarity fix).
- Out of scope: SoftwarePlan rework. Live WSL install in Smoke. Primary metal. Re-doing T1/T2 HostReview projection. Dual draft compilers / chip-axis resolve (separate Strong).
- Ponytail: smallest additive field + rename; no new C# “AcceptanceFacts” type unless WriteExpectedEvidence + record already force it.
- Commit style: `docs:` · `feat(scope):` · `fix(scope):` …
- Focused tests while iterating; `just check` before final task commit.
- Work on branch `sdd/145-acceptance-facts` in worktree; commit when a task’s Commit step says so.
- After land: pointer comment on #142; close #145 with summary; close #142 map when children done.

## File map

| File | Responsibility |
|------|----------------|
| `src/WinMint.Orchestrator/ServicingWorkspace.cs` | `ExpectedEvidenceFile` + `packageWireHonest` |
| `src/WinMint.Orchestrator/ImageServicing.Evidence.cs` | Always write honesty from `plan.PackageWireHonest` |
| `src/WinMint.Orchestrator/ImageServicing.cs` | Schema const stays v1 (comment if needed) |
| `tools/host/Assert-ImageEvidenceCore.ps1` | Rename ReleaseStrict; Gate B = wipe-ready; fail-closed on missing honesty |
| `tools/apply/Invoke-HostApply.ps1` | Pre-Apply ReleaseStrict; Flash text uses wipe-ready from expected-evidence |
| `tools/apply/Assert-ApplyEvidence.ps1` | Wipe-ready Gate B for DMA settle / Flash-adjacent paths |
| `tests/contract/Test-ApplyEvidence.ps1` | Predicate unit checks + mutate honesty → fail |
| `tests/fixtures/apply-evidence/expected-evidence.json` | Add `packageWireHonest` |
| `tests/WinMint.Tests/ExpectedEvidenceWslWireTests.cs` (or sibling) | Serialize/write includes honesty |
| `CONTEXT.md` | Gate B gloss: PS Gate B = wipe-ready; ReleaseStrict = input gate |

---

### Task 1: Freeze `packageWireHonest` on expected-evidence

**Files:**
- Modify: `ServicingWorkspace.cs` (`ExpectedEvidenceFile`)
- Modify: `ImageServicing.Evidence.cs` (`WriteExpectedEvidence`)
- Modify: fixture `tests/fixtures/apply-evidence/expected-evidence.json` (+ any other expected-evidence fixtures)
- Test: extend `ExpectedEvidenceWslWireTests` (or add focused test) — written JSON includes `packageWireHonest` matching plan slice

- [ ] **Step 1: Failing test** — expected-evidence bytes/JSON must contain `packageWireHonest` from plan
- [ ] **Step 2: Add property; always write from `plan.PackageWireHonest`**
- [ ] **Step 3: Update fixtures; tests pass**
- [ ] **Step 4: Commit**

```
feat(host): freeze packageWireHonest on expected-evidence
```

---

### Task 2: Rename ReleaseStrict; Gate B = wipe-ready in asserts

**Files:**
- Modify: `tools/host/Assert-ImageEvidenceCore.ps1`
- Modify: `tools/apply/Assert-ApplyEvidence.ps1`
- Modify: `tools/apply/Invoke-HostApply.ps1` (pre-Apply only → ReleaseStrict)
- Modify: `tests/contract/Test-ApplyEvidence.ps1` (predicate self-checks)
- Grep/replace remaining `Test-WinMintIsGateB` / `Assert-WinMintGateB` call sites that mean lane∧strict

**Interfaces (PS):**
- `Test-WinMintIsReleaseStrict -Lane -PackageStrict` → lane eq Release ∧ strict
- `Assert-WinMintReleaseStrict` → throw with soft-Release message
- `Test-WinMintIsGateB -Lane -PackageStrict -PackageWireHonest` → Release ∧ strict ∧ honest
- `Assert-WinMintGateB` → requires honesty; fail-closed if honesty missing when wipe-ready path runs
- `Assert-WinMintImageEvidence`: when expected has `packageStrict`, assert wipe-ready using expected.lane / packageStrict / packageWireHonest (not lane∧strict alone)

- [ ] **Step 1: Failing contract** — Release+strict+honest true; Release+strict+!honest false; soft Release false; Test lane false; missing honesty + packageStrict throws
- [ ] **Step 2: Rename + implement wipe-ready helpers; wire ImageEvidence expected path**
- [ ] **Step 3: Fix all call sites; contract green**
- [ ] **Step 4: Commit**

```
feat(host): Gate B wipe-ready assert from expected-evidence honesty
```

---

### Task 3: Post-Apply Flash guidance + mutate-honesty bar

**Files:**
- Modify: `Invoke-HostApply.ps1` — after assert, Flash guidance uses wipe-ready from workdir `expected-evidence.json` (lane, packageStrict, packageWireHonest), not CLI `-PackageStrict` alone
- Modify: `tests/contract/Test-ApplyEvidence.ps1` — copy fixture, set `packageWireHonest=$false` (with Release+strict), assert fails Gate B / wipe-ready path
- Keep: Wizard/`HostReview.IsGateB` unchanged (already full claim)

- [ ] **Step 1: Failing contract** — dishonest expected-evidence fails wipe-ready assert
- [ ] **Step 2: Flash guidance reads expected-evidence**
- [ ] **Step 3: `just check` green**
- [ ] **Step 4: Commit**

```
fix(host): Flash guidance uses wipe-ready expected-evidence
```

---

### Task 4: CONTEXT polarity + map close-out

**Files:**
- Modify: `CONTEXT.md` Gate B paragraph + avoid-list
- Comment: #142 pointer; close #145

Suggested CONTEXT shape:
- Gate B predicate = `HostReview.IsGateB` / PS `Test-WinMintIsGateB` (Release ∧ package-strict ∧ packageWireHonest from review or expected-evidence).
- Apply input gate = `Test-WinMintIsReleaseStrict` (Release ∧ package-strict only) — not wipe-ready.
- Avoid: equating ReleaseStrict with wipe-ready; Flash guidance from lane∧strict alone.

- [ ] **Step 1: CONTEXT edit**
- [ ] **Step 2: `just check` green**
- [ ] **Step 3: Commit**

```
docs: Gate B wipe-ready vs ReleaseStrict polarity
```

- [ ] **Step 4: Comment on #142**; close #145 with summary (leave #142 close to controller after fresh Gate B)

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Single wipe-ready predicate mirrors `HostReview.IsGateB` | 2 |
| Honesty signal in facts asserts consume | 1 |
| Thin PS adapter; no second planner | 2–3 |
| Contract: mutate honesty → Gate B fails | 3 |
| Smoke/Apply share one Gate B helper | 2 |
| CONTEXT polarity | 4 |
| `just check` green | 3–4 |
