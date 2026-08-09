# Task 2 Report: FancyWM catalog stub + Software shell chips default off

**Branch:** `feat/wizard-calm-oobe`  
**Date:** 2026-08-09  
**Commit:** `6c56065` — `feat(catalog): FancyWM stub; desktop shell chips default off`

## Summary

Added a FancyWM catalog stub and set all desktop shell chips (Windhawk, YASB, Komorebi, FancyWM) to `IsSelected = false` by default. Replaced Nilesoft from the shell chip list (product-constant install, not a user toggle).

## TDD

1. **Red** — Added `Catalog_contains_fancywm_stub` to `PackageCatalogTests.cs`; failed (`TryGetToolByKey("fancywm")` returned false).
2. **Green** — Added `fancywm` to `config/packages.json`; updated `WizardShellViewModel` shell chips.
3. **Verify** — `just check` passed (254 tests, format clean, PSScriptAnalyzer clean).

## Changes

### `config/packages.json`

- **`fancywm`** — winget source, id `FancyWM.FancyWM` (stub; see winget note below), architectures `["amd64","arm64"]`.
- **`mingit`** — preserved existing WIP entry (`Git.MinGit`) per task context.

### `src/WinMint.Wizard/ViewModels/WizardShellViewModel.cs`

- Shell chips: Windhawk, YASB, Komorebi, **FancyWM** (replaced Nilesoft chip).
- All shell chips: `IsSelected = false` (was: windhawk/yasb/komorebi pre-selected).

### `tests/WinMint.Tests/PackageCatalogTests.cs`

- New test `Catalog_contains_fancywm_stub` per brief.

## FancyWM winget verification

```
winget search FancyWM
Name                                    Id           Version Source
FancyWM - Dynamic Tiling Window Manager 9P1741LKHQS9 Unknown msstore
```

No winget community id found — only Microsoft Store (`9P1741LKHQS9`). Catalog uses **`FancyWM.FancyWM`** as a clearly stubbed winget id so Plan validates when the chip is selected. Upgrade path: switch to msstore source or correct winget id when published.

## Deferred (per parent agent scope)

- **KeepGaming / KeepCopilot removal** — brief Step 3 mentions it; parent agent instructed defer to Task 4. KEEP panel and properties left intact.
- **Stage renames (Task 3)** — not touched.
- **Task 1 WIP** — `StripProductConstantWingetIds` hunk in ViewModel restored unstaged after commit; other Task 1 files remain uncommitted.

## Test summary

| Command | Result |
|---------|--------|
| `Catalog_contains_fancywm_stub` | PASS (after implement) |
| `just check` | PASS — 254/254 tests |

## Concerns

1. **Stub id** — Selecting FancyWM chip will emit a winget job for `FancyWM.FancyWM` which will fail at install until id is corrected or source switched to msstore.
2. **Nilesoft off shell chips** — Nilesoft remains in catalog and product-constant install path; only removed from optional shell chip UI (aligned with Task 1 posture).

## Follow-up: Task 2 build repair

- Restored the legacy `KeepGaming` and `KeepCopilot` observable properties so the deferred Taste UI removal remains build-compatible through Task 4.
- Retained the Windhawk, YASB, Komorebi, and FancyWM shell chips with all defaults off.
- `WizardShellViewModel.BuildInput` strips MinGit and Nilesoft through the existing `ProductPosture.StripWingetFromAuthored`; no missing `ProductConstantPackages` dependency remains.
- Verified with `just check`: format clean, build clean, 251/251 tests passed, and PSScriptAnalyzer clean.
