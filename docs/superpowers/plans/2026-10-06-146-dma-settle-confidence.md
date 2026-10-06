# #146 DMA settle confidence — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deepen DMA settle confidence: one outcome (hard / soft / latch) behind a small interface; Win32 region + DeviceRegion stay adapters. Gate B host-asserts bundle settle completeness when DMA enabled.

**Architecture:** Callers (Machine setup, FirstLogon settle, resume) use one settle-confidence module. Final hard-field snapshot remains authoritative; intermediate re-apply stays fail-open with locality inside the module. Prefer hard locale/Geo/TZ re-verify on resume before jobs. Gate B reads `payload/bundle.json` settle target completeness when DMA enabled.

**Tech Stack:** .NET 11 / C#, PowerShell Gate B asserts, xUnit (`DmaSettleTests`).

## Global Constraints

- Spec: GitHub issue #146 (Part of #142). Map decisions in #142. ADR-003 unchanged (Ireland DeviceRegion 68 latch).
- One settle-confidence module; Win32 region + DeviceRegion stay adapters.
- Final hard-field snapshot authoritative; intermediate re-apply fail-open inside the module.
- Resume path: document and test hard locale/Geo/TZ re-verify after reboot (prefer re-verify before jobs) — replace blind `settle.resumeSkip` of visible hard fields.
- Gate B host assert: read `payload/bundle.json` settle target completeness (locale, geoId, timeZoneId, locationServicesEnabled) when DMA enabled — host-side only.
- Out of scope: Changing Ireland DeviceRegion 68. Soft location → hard fail (unless grill reopens).
- Ponytail: extract the smallest module that unifies outcomes; do not invent a second settle pipeline.
- No profile schema bump; no CONTEXT/ADR edits unless polarity changes (ADR-003 stays).
- Commit style: `docs:` · `feat(scope):` · `fix(scope):` …
- Focused tests while iterating; `just check` before final task commit.
- Work on branch `sdd/146-dma-settle` in worktree; commit when a task’s Commit step says so.
- After land: pointer comment on #142; leave issue close to controller.

## File map

| File | Responsibility |
|------|----------------|
| `src/WinMint.Provisioning/` (new small type or partial) | Settle-confidence outcomes + orchestration helpers |
| `src/WinMint.Provisioning/ProvisioningSession.cs` | Call module from Shell settle / resume / setup latch |
| `src/WinMint.Provisioning/Win32RegionSnapshot.cs` | Adapter; optional apply verify — keep fail-open locality in module |
| `src/WinMint.Provisioning/ProvisioningSession.Types.cs` | `IRegionSnapshot` unchanged contract if possible |
| `tools/apply/Assert-ApplyEvidence.ps1` | Gate B: bundle settle completeness when dma enabled |
| `tests/WinMint.Tests/DmaSettleTests.cs` | Cross new interface; latch soft vs hard preserved |
| Contract/assert tests for Gate B bundle settle | as existing harness patterns dictate |

---

### Task 1: Settle-confidence module + DmaSettleTests

**Files:**
- Create/modify: small settle-confidence type in `WinMint.Provisioning`
- Modify: `ProvisioningSession.cs` to call it for Shell settle loop (hard/soft/latch outcomes)
- Keep: DeviceRegion Ireland latch policy inside/alongside module without changing ADR-003
- Test: `DmaSettleTests` — existing cases pass through new interface; add drift re-stamp if module owns intermediate re-apply

**Interfaces:**
- Outcome: hard ok / soft warn / hard fail / latch fail (names match existing phase codes where possible: `settle.ok`, `settle.hardMismatch`, `settle.locationWarn`, `settle.deviceRegion*`)
- Intermediate probe/re-apply failures fail-open; final snapshot gates

- [ ] **Step 1: Write/adjust failing tests** that require the module seam (e.g. re-stamp on hard-field drift; existing hard-mismatch still fails)
- [ ] **Step 2: Extract module; wire RunSettleAsync / setup latch**
- [ ] **Step 3: Tests pass**
- [ ] **Step 4: Commit**

```
feat(provisioning): DMA settle confidence module
```

---

### Task 2: Resume hard-field re-verify before jobs

**Files:**
- Modify: `ProvisioningSession.cs` resume branch (today notes `settle.resumeSkip` and only runs DeviceRegion latch)
- Test: resume path re-verifies hard locale/Geo/TZ (and fails hard mismatch) before jobs; document in code comment why

- [ ] **Step 1: Failing resume re-verify test**
- [ ] **Step 2: Prefer re-verify before jobs; keep DeviceRegion latch**
- [ ] **Step 3: Tests pass; Commit**

```
fix(provisioning): re-verify DMA hard fields on checkpoint resume
```

---

### Task 3: Gate B bundle settle completeness + gate green

**Files:**
- Modify: `tools/apply/Assert-ApplyEvidence.ps1` (or shared assert) to read `payload/bundle.json` when DMA enabled and require settle fields
- Tests: contract or host assert fixture — fails on incomplete DMA settle in bundle when dma.enabled
- [ ] **Step 1: Failing assert test/fixture**
- [ ] **Step 2: Implement host-side completeness check**
- [ ] **Step 3: `just check` green**
- [ ] **Step 4: Commit**

```
feat(host): Gate B assert DMA settle completeness in bundle
```

- [ ] **Step 5: Comment on #142** with module + assert locations; leave issue close to controller

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| One settle-confidence module | Task 1 |
| Intermediate re-apply fail-open; final snapshot authoritative | Task 1 |
| Latch soft vs hard preserved (ADR-003) | Task 1 |
| Resume hard re-verify | Task 2 |
| Gate B bundle settle completeness | Task 3 |
| `just check` green | Task 3 |
| Comment #142 | Task 3 |
