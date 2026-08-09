# Wizard Calm OOBE Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Avalonia Wizard as Source → Account → Software → Review with WinMint/Fluent calm OOBE chrome, locked gaming+Copilot-app strip (Edge Copilot kept), desktop-shell stubs, and a Plan-sourced vanilla→WinMint full diff on Review.

**Architecture:** Keep `WizardSession` Avalonia-free. Orchestrator owns product locks (always-strip AppX set; never stamp Edge Copilot-kill). Wizard views rename stages; Review calls a new `PlanDiff` projector over `BuildArtifacts`. FancyWM is catalog-stub only until winget id is verified.

**Tech Stack:** C# / Avalonia Fluent / xUnit (`just check`) / `WinMint.Orchestrator` + `WinMint.Wizard`

**Spec:** [docs/superpowers/specs/2026-08-09-wizard-calm-oobe-redesign.md](../specs/2026-08-09-wizard-calm-oobe-redesign.md)

---

## File map

| File | Responsibility |
|------|----------------|
| `src/WinMint.Orchestrator/ProductOfflinePolicies.cs` | Stop stamping CopilotKill (Edge Copilot kept) |
| `src/WinMint.Orchestrator/ProductRequiredStrip.cs` (new) | Always-union gaming + `Microsoft.Copilot` into AppX remove-list at Plan |
| `src/WinMint.Orchestrator/BuildPlan.cs` | Apply required strip before stages/jobs |
| `src/WinMint.Orchestrator/PoliciesProfile.cs` + ADR-009 | Document `keepCopilot` obsolete for Edge kill; Edge Copilot always kept |
| `config/packages.json` | FancyWM stub entry |
| `src/WinMint.Wizard/WizardStageGates.cs` | Source=0 Account=1 Software=2 Review=3 |
| `src/WinMint.Wizard/Views/*StepView.axaml(+.cs)` | Rename Media/You/Taste/Included → Source/Account/Software/Review |
| `src/WinMint.Wizard/ViewModels/WizardShellViewModel.cs` | Stage commands, Software chips, no Keep* toggles, shell defaults off |
| `src/WinMint.Wizard/MainWindow.axaml` + `App.axaml` | Nav labels + calm chip styles |
| `src/WinMint.Wizard/PlanDiff.cs` (new) | Avalonia-free vanilla diff text from `BuildArtifacts` |
| `src/WinMint.Wizard/IncludedReceipt.cs` | Keep quiet receipt; align MinGit/Nilesoft; drop Copilot-off when Edge Copilot kept |
| `tests/WinMint.Tests/*` | Stage gates, strip lock, PlanDiff, FancyWM stub, BrowserPolicy updates |

---

### Task 1: Product lock — Edge Copilot kept, AppX Copilot + gaming always stripped

**Files:**
- Create: `src/WinMint.Orchestrator/ProductRequiredStrip.cs`
- Modify: `src/WinMint.Orchestrator/ProductOfflinePolicies.cs`
- Modify: `src/WinMint.Orchestrator/BuildPlan.cs` (Plan path where `RemoveProvisionedAppx` feeds stages/jobs)
- Modify: `src/WinMint.Orchestrator/PoliciesProfile.cs` (doc comment)
- Modify: `docs/decisions/ADR-009-product-constant-policies.md`
- Test: `tests/WinMint.Tests/BrowserPolicyPlanTests.cs`
- Test: `tests/WinMint.Tests/ProductRequiredStripTests.cs` (new)

- [ ] **Step 1: Write failing tests**

```csharp
// tests/WinMint.Tests/ProductRequiredStripTests.cs
public class ProductRequiredStripTests
{
    [Fact]
    public void Union_adds_copilot_and_gaming_when_missing()
    {
        IReadOnlyList<string> merged = ProductRequiredStrip.UnionAppx(["Microsoft.BingNews"]);
        Assert.Contains("Microsoft.Copilot", merged);
        Assert.Contains("Microsoft.GamingApp", merged);
        Assert.Contains("Microsoft.BingNews", merged);
    }

    [Fact]
    public void Plan_never_stamps_TurnOffWindowsCopilot_even_when_keepCopilot_false()
    {
        Profile profile = /* lab with policies keepCopilot false, empty appx */;
        var planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk);
        string specs = string.Join(';', planned.Value.Stages.Stages
            .Where(s => s.Opcode == ServicingOpcode.StampOfflinePolicies)
            .SelectMany(s => s.Params.Values));
        Assert.DoesNotContain("TurnOffWindowsCopilot", specs, StringComparison.Ordinal);
        Assert.DoesNotContain("HubsSidebarEnabled", specs, StringComparison.Ordinal);
    }
}
```

Update `BrowserPolicyPlanTests` that currently expect Copilot-kill when `KeepCopilot: false`.

- [ ] **Step 2: Run tests — expect FAIL**

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~ProductRequiredStripTests|FullyQualifiedName~BrowserPolicyPlanTests"
```

- [ ] **Step 3: Implement**

```csharp
// ProductRequiredStrip.cs
public static class ProductRequiredStrip
{
    public static IReadOnlyList<string> AppxIds { get; } =
    [
        ..KeepFlagPresets /* or duplicate gaming+copilot arrays — prefer shared list from KeepFlagPresets public helpers */,
    ];

    public static IReadOnlyList<string> UnionAppx(IReadOnlyList<string> profileAppx) { /* dedupe OrdinalIgnoreCase */ }
}
```

In `ProductOfflinePolicies.Compose`: **never** `rows.AddRange(CopilotKill)` (leave CopilotKill array in file commented/obsolete or delete).

In `BuildPlan.Plan`: `appx = ProductRequiredStrip.UnionAppx(profile.RemoveProvisionedAppx)` for RemoveProvisionedAppx stage + safetyNet job decisions (use effective list consistently).

`PoliciesProfile.KeepCopilot` XML doc: obsolete for Edge kill; Edge Copilot always kept; AppX strip is `ProductRequiredStrip`.

ADR-009: update decision bullet for keepCopilot / Copilot-kill.

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```powershell
git add src/WinMint.Orchestrator docs/decisions/ADR-009-product-constant-policies.md tests/WinMint.Tests
git commit -m "fix(orchestrator): always strip Copilot app + gaming; keep Edge Copilot"
```

---

### Task 2: FancyWM catalog stub + Software shell chips default off

**Files:**
- Modify: `config/packages.json`
- Modify: `src/WinMint.Wizard/ViewModels/WizardShellViewModel.cs` (shell chips — after rename in Task 3 if conflict, do chip list here)
- Test: `tests/WinMint.Tests/PackageCatalogTests.cs`

- [ ] **Step 1: Failing test — FancyWM key resolves as stub**

```csharp
[Fact]
public void Catalog_contains_fancywm_stub()
{
    Assert.True(PackageCatalog.Default.TryGetToolByKey("fancywm", out PackageToolEntry? tool));
    Assert.Equal("winget", tool!.Source);
    Assert.False(string.IsNullOrWhiteSpace(tool.InstallId));
}
```

Use a placeholder install id clearly marked stub, e.g. `Alfaro.FancyWM` or `FancyWM.FancyWM` — verify with `winget search FancyWM` on ARM64 before finalizing; if unknown, still add catalog row with `id` documented as stub and architectures `["amd64","arm64"]` so Plan validates when selected.

- [ ] **Step 2: Run test — FAIL (missing key)**

- [ ] **Step 3: Add packages.json entry + set Shell chips to Windhawk/YASB/Komorebi/FancyWM with `IsSelected = false` for all**

Remove KeepGaming / KeepCopilot properties and Taste UI bindings (full removal in Task 3–4 if still present).

- [ ] **Step 4: PASS + commit**

```powershell
git commit -m "feat(catalog): FancyWM stub; desktop shell chips default off"
```

---

### Task 3: Rename stages Source / Account / Software / Review

**Files:**
- Modify: `src/WinMint.Wizard/WizardStageGates.cs`
- Rename/move views: `MediaStepView`→`SourceStepView`, `YouStepView`→`AccountStepView`, `TasteStepView`→`SoftwareStepView`, `IncludedStepView`→`ReviewStepView` (axaml + code-behind + `MainWindow.axaml`)
- Modify: `WizardShellViewModel.cs` step flags/commands (`GoToSourceCommand`, …)
- Modify: `tests/WinMint.Tests/WizardStageGatesTests.cs`
- Modify: any strings `MEDIA`/`YOU`/`TASTE`/`INCLUDED`

- [ ] **Step 1: Update `WizardStageGatesTests` to Source=0 … Review=3 and gate rules (ISO before leave Source; password before Review/Build)**

```csharp
public const int Source = 0, Account = 1, Software = 2, Review = 3;
```

- [ ] **Step 2: FAIL on old constants / renames**

- [ ] **Step 3: Implement renames + MainWindow scrub `1 Source` … `4 Review` (plain text, not ALLCAPS theater)**

Software step copy: plain (“Apps, desktop shell, WSL, cleanup”) — no “Taste”.

- [ ] **Step 4: `just check` green**

- [ ] **Step 5: Commit**

```powershell
git commit -m "feat(wizard): Source Account Software Review stage shell"
```

---

### Task 4: Software step UX — recommended only, Use defaults, no Keep toggles

**Files:**
- Modify: `SoftwareStepView.axaml`
- Modify: `WizardShellViewModel.cs` / `WizardSession.cs`
- Modify: `tests/WinMint.Tests/WizardSessionTests.cs`

- [ ] **Step 1: Tests — compose always expands recommended with gaming+Copilot app present; KeepCopilot/KeepGaming absent from input or ignored**

```csharp
[Fact]
public void Compose_forces_recommended_strip_without_keep_overlays()
{
    var result = WizardSession.ComposeAndPlan(Lab(preset: KeepFlagPresets.Recommended));
    Assert.True(result.Succeeded);
    var profile = BuildPlan.TryParseProfile(result.ProfileUtf8!).Value;
    Assert.Contains("Microsoft.Copilot", profile.RemoveProvisionedAppx);
    Assert.Contains("Microsoft.GamingApp", profile.RemoveProvisionedAppx);
}
```

Remove UI ToggleButtons for Xbox & gaming / Copilot. Preset chips: primary **Recommended** only (Acceptance/Empty behind Advanced if kept).

Add **Use defaults** command: clear package chips, preset recommended, jump to Review.

- [ ] **Step 2–4: TDD implement + `just check`**

- [ ] **Step 5: Commit**

```powershell
git commit -m "feat(wizard): Software step defaults; remove Keep gaming/Copilot UI"
```

---

### Task 5: PlanDiff — vanilla → WinMint projector (Avalonia-free)

**Files:**
- Create: `src/WinMint.Wizard/PlanDiff.cs`
- Test: `tests/WinMint.Tests/PlanDiffTests.cs`

- [ ] **Step 1: Failing tests for section headers + sample rows**

```csharp
[Fact]
public void Format_includes_offline_and_live_sections()
{
    BuildArtifacts artifacts = BuildPlan.Plan(LabProfileWithWingetAndOnlineDebloat()).Value;
    string text = PlanDiff.Format(artifacts, LabProfileWithWingetAndOnlineDebloat());
    Assert.Contains("During image build", text, StringComparison.OrdinalIgnoreCase);
    Assert.Contains("After first sign-in", text, StringComparison.OrdinalIgnoreCase);
    Assert.Contains("MinGit", text, StringComparison.OrdinalIgnoreCase);
    Assert.Contains("Nilesoft", text, StringComparison.OrdinalIgnoreCase);
}

[Fact]
public void Format_marks_product_constants_as_always()
{
    // assert a line contains "always" near MinGit / OneDrive
}
```

- [ ] **Step 2: FAIL (type missing)**

- [ ] **Step 3: Implement `PlanDiff.Format(BuildArtifacts artifacts, Profile profile)`**

Map:
- Offline: stages (`RemoveProvisionedAppx`, caps/features, `InjectSurfaceDrivers`, `StampOfflinePolicies` digests/labels, `StampShell`, `StagePayload`, `ExportWim` lane)
- Live: implied DMA settle from profile.dma; jobs by kind (`appx.safetyNet`, `onedrive.uninstall`, `reservedStorage.disable`, `winget`/`winget.import`, `wsl`, `doh.set`, …)
- Each line: `label (id) — always|you chose`

Use friendly maps where `IncludedReceipt` already has AppX labels; extend for jobs.

- [ ] **Step 4: PASS + commit**

```powershell
git commit -m "feat(wizard): PlanDiff vanilla-to-WinMint projector"
```

---

### Task 6: Review step UI — short receipt + Show full plan

**Files:**
- Modify: `ReviewStepView.axaml`
- Modify: `WizardShellViewModel.cs` (`FullPlanText`, `IsFullPlanVisible`, toggle command)
- Modify: `IncludedReceipt.cs` — quiet block: drop “Copilot off”; keep MinGit/Nilesoft/Edge policies/OneDrive/…

- [ ] **Step 1: Test quiet block no longer says Copilot off; still lists MinGit**

```csharp
string text = IncludedReceipt.FormatQuietBlock(keepCopilot: false, braveSelected: false);
Assert.DoesNotContain("Copilot off", text, StringComparison.Ordinal);
Assert.Contains("MinGit", text, StringComparison.Ordinal);
```

(Optionally simplify `FormatQuietBlock` signature later — YAGNI: stop passing keepCopilot if unused.)

- [ ] **Step 2: Review XAML** — short receipt bindings; Expander or Toggle “Show full plan” bound to `FullPlanText` from `PlanDiff.Format` after successful compose/plan

- [ ] **Step 3: Wire `RefreshReceipt` / plan path to set `FullPlanText`

- [ ] **Step 4: `just check` + commit**

```powershell
git commit -m "feat(wizard): Review full plan expander (vanilla diff)"
```

---

### Task 7: Calm visual polish (WinMint + Fluent)

**Files:**
- Modify: `App.axaml` chip styles (less `CornerRadius=999` candy; calmer padding)
- Modify: `MainWindow.axaml` step title spacing / progress
- Ensure brand mark remains in titlebar

- [ ] **Step 1: Adjust styles to sober toggles; keep FluentTheme + OS accent**

- [ ] **Step 2: Manual smoke — `dotnet run --project src/WinMint.Wizard` (light/dark)

- [ ] **Step 3: Commit**

```powershell
git commit -m "style(wizard): calm OOBE Fluent chips and step chrome"
```

---

### Task 8: Docs + sample honesty + final check

**Files:**
- Modify: `CONTEXT.md` Wizard blurb if stage names mentioned
- Modify: `docs/DESIGN.md` shipped line / grill if Taste mentioned
- Modify: `samples/sl7.profile.json` — ensure Copilot+gaming remain on remove-list; no `policies.keepCopilot: true`
- Run: `just check`

- [ ] **Step 1: Doc greps for Taste/You/Included/KeepCopilot UI claims — update**

- [ ] **Step 2: `just check`**

- [ ] **Step 3: Commit**

```powershell
git commit -m "docs: Wizard calm OOBE redesign index + ADR/CONTEXT"
```

---

## Spec coverage check

| Spec item | Task |
|-----------|------|
| 4 plain steps | 3 |
| Software chips + shell stubs | 2, 4 |
| No Keep gaming/Copilot UI | 4 |
| Always strip gaming + Copilot app | 1 |
| Keep Edge Copilot | 1 |
| MinGit/Nilesoft not chips | already + receipt Task 6 |
| Review short + full vanilla diff | 5, 6 |
| WinMint + Fluent visual | 7 |
| FancyWM stub | 2 |
| ADR/docs | 1, 8 |

## Out of scope (do not implement)

T2–T4 deepening, Smoke harness UX, verifying FancyWM winget publish beyond stub, BitLocker / MSA accounts.
