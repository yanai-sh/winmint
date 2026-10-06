# #150 ChipAxisResolve — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One deep module turns chip keys + desktop axes into `PackageSelection` + selection labels. Station seed and Wizard both call that seam; Wizard stops owning axis→package rules.

**Architecture:** New Orchestrator module `ChipAxisResolve`: tool chip keys + WSL tokens + taskbar surface + komorebi → packages + labels. Filters non-package tool keys inside the module. `StationOutcomes.TrySeed` calls it with outcome chip lists and `TaskbarWindows` (YASB never seeded). Wizard maps UI state to the same args. Advanced multiline merges stay in `WizardDraftCompile`.

**Tech Stack:** .NET 11 / C#, xUnit (`StationOutcomesTests`, new `ChipAxisResolveTests`, Wizard session tests retargeted).

## Global Constraints

- Spec: GitHub issue #150 (architecture review Strong #2).
- ADR-015 desktop axes unchanged; outcome names never enter Profile (ADR-005).
- YASB / `TaskbarYasb` remains user-refine only — Station outcomes always pass `TaskbarWindows`.
- `PackageCatalog` stays chip/token → install id wire only.
- Delete Wizard `ResolvePackages` / `SelectedLabels` bodies; no thin forwarder left on `SoftwareStageViewModel`.
- Out of scope: Dual shipping-draft compilers (WizardDraftCompile vs CuratedDefaults). Gate B / #145. Catalog quality package-set. Smoke S4 deepen.
- Ponytail: one small static module + record result; do not invent a port.
- No `winmint.profile/v1` bump. CONTEXT only if a coined term appears (unlikely — reuse existing chip / desktop vocabulary).
- Commit style: `docs:` · `feat(scope):` · `fix(scope):` …
- Focused tests while iterating; `just check` before final task commit.
- Work on branch `sdd/chip-axis-resolve` in worktree; commit when a task’s Commit step says so.
- After land: close the issue with summary.

## File map

| File | Responsibility |
|------|----------------|
| `src/WinMint.Orchestrator/ChipAxisResolve.cs` (new) | Deep resolve: keys + axes → `PackageSelection` + labels |
| `src/WinMint.Orchestrator/StationOutcomes.cs` | Call `ChipAxisResolve`; drop private duplicate inject/label logic |
| `src/WinMint.Wizard/ViewModels/SoftwareStageViewModel.cs` | Remove `ResolvePackages` / `SelectedLabels`; expose chip/axis snapshot for compile |
| `src/WinMint.Wizard/ViewModels/WizardViewModel.cs` | Call `ChipAxisResolve` when building `WizardDraftRequest` |
| `tests/WinMint.Tests/ChipAxisResolveTests.cs` (new) | Axis inject (yasb, komorebi+whkd), label order, IsPackageTool filter, failures |
| `tests/WinMint.Tests/StationOutcomesTests.cs` | Still green; Power still seeds komorebi packages via module |
| `tests/WinMint.Tests/WizardSessionTests.cs` | Stop calling `ResolvePackages`; hit module or draft path |

---

### Task 1: `ChipAxisResolve` module + tests

**Files:**
- Create: `ChipAxisResolve.cs`
- Create: `ChipAxisResolveTests.cs`

**Interface (sketch — implement to tests):**
- Input: tool chip keys, WSL tokens, taskbar surface (`windows` / `yasb`), komorebi bool
- Behavior: filter tool keys with `CuratedPackageChips.IsPackageTool`; if yasb taskbar append `yasb`; if komorebi append `komorebi`, `whkd`; `ResolveToolKeys` + `ResolveWslTokens`; build labels (taskbar, Komorebi, chip/WSL labels) — same polarity as today’s `BuildLabels`
- Output: `Result<(PackageSelection Packages, IReadOnlyList<string> SelectionLabels), Failure>` or a small named record

- [ ] **Step 1: Failing tests** — yasb injects yasb package; komorebi injects komorebi+whkd; windows+!komorebi does not; non-package tool key filtered; unknown tool key fails via catalog
- [ ] **Step 2: Implement module**
- [ ] **Step 3: Tests pass**
- [ ] **Step 4: Commit**

```
feat(host): ChipAxisResolve for chips and desktop axes
```

---

### Task 2: StationOutcomes calls the module

**Files:**
- Modify: `StationOutcomes.cs` — `Seed` builds args, calls `ChipAxisResolve`, fills `StationSeed`
- Keep: outcome chip lists / debloat / `TaskbarWindows` polarity
- Test: `StationOutcomesTests` still green (Power packages include komorebi ids; taskbar still windows)

- [ ] **Step 1: Wire Seed through ChipAxisResolve; delete private BuildLabels / inline inject**
- [ ] **Step 2: StationOutcomesTests pass**
- [ ] **Step 3: Commit**

```
refactor(host): StationOutcomes seeds via ChipAxisResolve
```

---

### Task 3: Wizard compiles through ChipAxisResolve

**Files:**
- Modify: `SoftwareStageViewModel.cs` — remove `ResolvePackages` / `SelectedLabels`; keep selection state helpers needed for UI / draft args
- Modify: `WizardViewModel.cs` — map selected chip keys, WSL tokens, desktop axes → `ChipAxisResolve` → `WizardDraftRequest`
- Modify: `WizardSessionTests.cs` (and any other callers of `ResolvePackages`)

- [ ] **Step 1: Failing/adjust tests** that called `ResolvePackages`
- [ ] **Step 2: Wizard uses module; delete shallow Wizard resolve**
- [ ] **Step 3: `just check` green**
- [ ] **Step 4: Commit**

```
refactor(wizard): draft packages via ChipAxisResolve
```

- [ ] **Step 5: Close issue** with module + call-site summary

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| One deep resolve seam | 1 |
| Station + Wizard share it | 2–3 |
| YASB refine-only | 2 |
| IsPackageTool inside module | 1 |
| No Wizard ResolvePackages/SelectedLabels | 3 |
| `just check` green | 3 |
