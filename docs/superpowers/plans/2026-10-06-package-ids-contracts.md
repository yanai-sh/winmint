# PackageIds Contracts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One Contracts home for the four winget IDs shared by Orchestrator and Provisioning, plus Orchestrator-local chip-key consts and Wizard surface-token dedupe.

**Architecture:** Flat `WinMint.Contracts.PackageIds` holds Yasb / Komorebi / Cursor / ZenBrowser install IDs. ProductPosture keeps composition and aliases Yasb/Komorebi to `PackageIds`. ShellDesktopLayout / ShellChromeLayout drop local winget ID consts. Chip inject keys live in Orchestrator `PackageChips` (not Contracts). Wizard `DesktopSelectionViewModel` uses `StationOutcomes.Taskbar*` instead of its own literals. Catalog drift is caught by extending `PackagesProof.MissingProductConstants`.

**Tech Stack:** .NET / C#, xUnit (`PackagesProofTests`, existing Shell* / ChipAxis / Wizard tests).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-10-06-package-ids-contracts-design.md` (streamlined).
- Contracts only: the four cross-boundary winget IDs. No chip keys, surface labels, `thide.exe`, scoop toolbox, or AppX/DoH in Contracts.
- Surface token ≠ chip key: `StationOutcomes.TaskbarYasb` and `PackageChips.Yasb` stay separate consts even if both equal `"yasb"`.
- Provisioning must not reference Orchestrator.
- No CONTEXT/ADR; no `winmint.profile/v1` bump; no codegen from `packages.json`.
- Ponytail: flat consts; delete duplicates; do not invent nested program types.
- Commit style: `docs:` · `feat(scope):` · `fix(scope):` …
- Focused tests while iterating; `just check` before the last commit.
- Out of scope: wide ManagedPrograms bag; tHide pins; moving ProductPosture composition.

## File map

| File | Responsibility |
|------|----------------|
| `src/WinMint.Contracts/PackageIds.cs` (new) | Four winget install ID consts |
| `src/WinMint.Orchestrator/PackagesProof.cs` | Sync-check PackageIds in `MissingProductConstants` |
| `src/WinMint.Orchestrator/ProductPosture.cs` | Yasb/Komorebi → `PackageIds.*`; keep Whkd/Brave/always-on lists |
| `src/WinMint.Provisioning/ShellDesktopLayout.cs` | Delete Yasb/Komorebi winget consts |
| `src/WinMint.Provisioning/ShellDesktop.cs` | Compare against `PackageIds` |
| `src/WinMint.Provisioning/ShellChromeLayout.cs` | Delete Cursor/Zen consts; use `PackageIds` |
| `src/WinMint.Provisioning/ProvisioningSession.JobRunner.Winget.cs` | Use `PackageIds` |
| `src/WinMint.Orchestrator/PackageChips.cs` (new) | Chip keys `yasb` / `komorebi` / `whkd` for inject |
| `src/WinMint.Orchestrator/ChipAxisResolve.cs` | Inject via `PackageChips` |
| `src/WinMint.Wizard/ViewModels/SoftwareStageViewModel.cs` | Desktop surface tokens → `StationOutcomes` |
| `src/WinMint.Wizard/Views/SoftwareStepView.axaml` | Keep `CommandParameter="yasb"` / `"windows"` (wire values = `StationOutcomes` strings) |
| Tests under `tests/WinMint.Tests/` | Prefer `PackageIds.*` where asserting those four IDs |

---

### Task 1: `PackageIds` + catalog sync

**Files:**
- Create: `src/WinMint.Contracts/PackageIds.cs`
- Modify: `src/WinMint.Orchestrator/PackagesProof.cs` (`MissingProductConstants`)
- Test: `tests/WinMint.Tests/PackagesProofTests.cs` (`Default_catalog_product_constants_are_non_stub_rows` already asserts `MissingProductConstants` is empty)

**Interfaces:**
- Produces: `public static class PackageIds` with `Yasb`, `Komorebi`, `Cursor`, `ZenBrowser` (`const string`)

- [ ] **Step 1: Write the failing sync coverage**

Extend `MissingProductConstants` so a missing `PackageIds` row fails the existing empty-assert test. First add the PackageIds loop *before* creating `PackageIds.cs`, OR add PackageIds with a deliberate wrong id to prove the test fails — prefer: add PackageIds correctly, then temporarily break one id to confirm fail, then restore.

Minimal extension inside `MissingProductConstants` (after the existing winget/scoop loops):

```csharp
foreach (string id in new[]
{
    PackageIds.Yasb,
    PackageIds.Komorebi,
    PackageIds.Cursor,
    PackageIds.ZenBrowser,
})
{
    if (!catalog.TryGetToolByInstallId(id, out PackageToolEntry? tool)
        || tool.Source is not PackageToolSource.Winget
        || tool.IsStub)
    {
        missing.Add($"packageIds:{id}");
    }
}
```

- [ ] **Step 2: Add `PackageIds.cs`**

```csharp
namespace WinMint.Contracts;

/// <summary>Winget install IDs compared by both Orchestrator and Provisioning.</summary>
public static class PackageIds
{
    public const string Yasb = "AmN.yasb";
    public const string Komorebi = "LGUG2Z.komorebi";
    public const string Cursor = "Anysphere.Cursor";
    public const string ZenBrowser = "Zen-Team.Zen-Browser";
}
```

- [ ] **Step 3: Run sync test**

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~Default_catalog_product_constants_are_non_stub_rows"
```

Expected: PASS (empty missing). Optionally flip `Yasb` to `"AmN.yasb.typo"`, re-run (FAIL with `packageIds:`), restore.

- [ ] **Step 4: Commit**

```
feat(contracts): PackageIds for cross-boundary winget identity
```

---

### Task 2: Rewire ProductPosture + Provisioning to `PackageIds`

**Files:**
- Modify: `src/WinMint.Orchestrator/ProductPosture.cs` — Yasb/Komorebi consts
- Modify: `src/WinMint.Provisioning/ShellDesktopLayout.cs` — delete winget consts
- Modify: `src/WinMint.Provisioning/ShellDesktop.cs` — use `PackageIds`
- Modify: `src/WinMint.Provisioning/ShellChromeLayout.cs` — delete Cursor/Zen consts; use `PackageIds`
- Modify: `src/WinMint.Provisioning/ProvisioningSession.JobRunner.Winget.cs` — use `PackageIds`
- Modify tests that reference `ShellDesktopLayout.YasbWingetId` / `ShellChromeLayout.CursorWingetId` / `ZenWingetId` → `PackageIds.*`
  - `tests/WinMint.Tests/ShellDesktopJobTests.cs`
  - `tests/WinMint.Tests/ShellChromeJobTests.cs`
  - `tests/WinMint.Tests/ShellChromeLayoutTests.cs`
  - `tests/WinMint.Tests/WingetJobsTests.cs`
  - Prefer `PackageIds.Yasb` over raw `"AmN.yasb"` in nearby asserts when touching those files (no drive-by rewrite of unrelated `"Anysphere.Cursor"` elsewhere)

**Interfaces:**
- Consumes: `PackageIds` from Task 1
- Produces: no new types; ProductPosture may keep `YasbWingetId` / `KomorebiWingetId` as aliases:

```csharp
public const string YasbWingetId = PackageIds.Yasb;
public const string KomorebiWingetId = PackageIds.Komorebi;
```

Prefer aliases so `BuildPlan` / existing ProductPosture call sites stay stable. Delete Shell* duplicates entirely (no aliases on Shell*).

- [ ] **Step 1: ProductPosture aliases**

Replace string literals for Yasb/Komorebi with `PackageIds.*` as above. Leave `WhkdWingetId = "LGUG2Z.whkd"` (Orchestrator-only; not in PackageIds).

- [ ] **Step 2: Provisioning rewire**

`ShellDesktop.cs`:

```csharp
bool yasb = ContainsId(request.WingetIds, PackageIds.Yasb);
bool komorebi = ContainsId(request.WingetIds, PackageIds.Komorebi);
```

`ShellChromeLayout.cs` / `JobRunner.Winget.cs`: replace `CursorWingetId` / `ZenWingetId` with `PackageIds.Cursor` / `PackageIds.ZenBrowser`. Delete the two `internal const` lines from `ShellChromeLayout`. Delete `YasbWingetId` / `KomorebiWingetId` from `ShellDesktopLayout`.

Add `using WinMint.Contracts;` where missing.

- [ ] **Step 3: Update Provisioning-facing tests** to `PackageIds.*`

- [ ] **Step 4: Run focused tests**

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~ShellDesktop|FullyQualifiedName~ShellChrome|FullyQualifiedName~WingetJobs|FullyQualifiedName~ProductPosture|FullyQualifiedName~PackagesProof"
```

Expected: PASS

- [ ] **Step 5: Commit**

```
refactor: consume PackageIds in ProductPosture and Provisioning
```

---

### Task 3: Orchestrator chip keys + Wizard surface tokens

**Files:**
- Create: `src/WinMint.Orchestrator/PackageChips.cs`
- Modify: `src/WinMint.Orchestrator/ChipAxisResolve.cs`
- Modify: `src/WinMint.Wizard/ViewModels/SoftwareStageViewModel.cs` (`DesktopSelectionViewModel`)
- Axaml: leave `CommandParameter="windows"` / `"yasb"` (must match `StationOutcomes.TaskbarWindows` / `TaskbarYasb` string values)
- Tests: `ChipAxisResolveTests`, `WizardSessionTests` — only if they break; prefer `PackageChips` / `StationOutcomes` when editing inject assertions

**Interfaces:**
- Produces:

```csharp
namespace WinMint.Orchestrator;

/// <summary>Catalog chip keys injected by desktop axes (not surface tokens).</summary>
public static class PackageChips
{
    public const string Yasb = "yasb";
    public const string Komorebi = "komorebi";
    public const string Whkd = "whkd";
}
```

- [ ] **Step 1: Add `PackageChips` and wire `ChipAxisResolve`**

```csharp
if (string.Equals(taskbarSurface, StationOutcomes.TaskbarYasb, StringComparison.Ordinal))
{
    resolveKeys = resolveKeys.Concat([PackageChips.Yasb]);
}

if (komorebi)
{
    resolveKeys = resolveKeys.Concat([PackageChips.Komorebi, PackageChips.Whkd]);
}
```

Do **not** alias `StationOutcomes.TaskbarYasb` to `PackageChips.Yasb`.

- [ ] **Step 2: Collapse Wizard desktop tokens**

In `DesktopSelectionViewModel`, delete `WindowsTaskbar` / `YasbTaskbar` consts. Use `StationOutcomes.TaskbarWindows` / `StationOutcomes.TaskbarYasb` everywhere those consts were used (property compares, `SelectTaskbar`, ApplyDefaults mapping).

- [ ] **Step 3: Run focused tests**

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~ChipAxisResolve|FullyQualifiedName~WizardSession|FullyQualifiedName~WizardViewModel|FullyQualifiedName~StationOutcomes"
```

Expected: PASS

- [ ] **Step 4: Commit**

```
refactor(host): PackageChips inject keys; Wizard uses StationOutcomes surfaces
```

---

### Task 4: Gate

- [ ] **Step 1: `just check`**

```powershell
just check
```

Expected: green

- [ ] **Step 2: Confirm no leftover Shell winget ID consts**

```powershell
rg "YasbWingetId|KomorebiWingetId|CursorWingetId|ZenWingetId" src/
```

Expected: only `ProductPosture.YasbWingetId` / `KomorebiWingetId` aliases (if kept), no Shell* definitions, no `"AmN.yasb"` / `"Anysphere.Cursor"` / `"Zen-Team.Zen-Browser"` / `"LGUG2Z.komorebi"` string literals in `src/WinMint.Provisioning` except path leaves like `"yasb"` config dir / `"komorebi"` variant folder names.

- [ ] **Step 3: Commit only if Task 4 left fixes** (otherwise skip empty commit)

```
fix: PackageIds plan gate cleanup
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| `PackageIds` four winget IDs in Contracts | 1 |
| Catalog sync for PackageIds (+ existing ProductPosture always-on) | 1 |
| ProductPosture composition stays; Yasb/Komorebi via PackageIds | 2 |
| ShellDesktop / ShellChrome delete local winget consts | 2 |
| Chip keys in Orchestrator, not Contracts | 3 |
| Wizard collapses surface tokens onto StationOutcomes | 3 |
| Surface token ≠ chip key | 3 |
| `just check` | 4 |
| No Provisioning → Orchestrator reference | 2 (layering) |
| Rejected wide bag / nested types / codegen | (out of scope) |
