# Complexity Deletion Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Prefer ponytail / YAGNI on every task. Use verification-before-completion before any “done” claim.

**Goal:** Lower cognitive and line complexity by deleting twin types, folding micro-files, and unifying design vocabulary on **Debloat** — net fewer production lines, zero new layers.

**Architecture:** Keep the three deep modules (BuildPlan → ImageServicing/`RunPlan` → ProvisioningSession). This is a **deletion + rename** pass only. No Contracts project, no new env bags, no new ports, no NuGet.

**Tech Stack:** Existing C# (.NET 11), pwsh servicing kernels, `just check`, xUnit tests.

**Sources:** [complexity-naming-audit canvas](../../../.cursor/projects/c-Users-yanai-Projects-winmint/canvases/complexity-naming-audit.canvas.tsx) · CONTEXT.md Language · docs/DESIGN.md · docs/design/KEEPFLAG.md · ADR-005.

## Global Constraints

```
DELETION LOCK
- Every task must net ≤ 0 production LOC (rename/doc sync may be ~0). Prefer delete/fold over extract.
- Forbid: Contracts assembly; SessionEnvironment split into new env types; new DI/container; new failure hierarchy; MediatR/mapper packages.
- Design vocabulary is in scope and may change. Canonical product word for remove-lists = Debloat (matches Profile JSON debloat.* and DebloatMode already in code). Retire Keep-flag / KeepFlag* as living names.
- Shell = Winlogon replacement only (Provisioning). Wizard UI chrome is not “Shell”.
- ADR history stays; add a one-line supersession / rename note — do not rewrite Accepted decision bodies wholesale.
- ARM64 host; elevate only Servicing pwsh -File; just check green after each task.
- Commit only when the user asks (or at task end if they chose execution with commits).
```

### Locked vocabulary decisions

| Concept | Canonical | Retire |
|---------|-----------|--------|
| Remove-lists + host presets | **Debloat** (`debloat.*`, `DebloatPresets`, `DebloatMode`) | Keep-flag, KeepFlag*, KEEPFLAG as living title |
| Guest process | **Provisioning Supervisor** / **ProvisioningSession** | — |
| Winlogon replacement | **Shell** (tenure) | Wizard “Shell” ViewModel name |
| Failure shape | **`Failure(Code, Message)`** in Orchestrator | PlanFailure, ServicingFailure, WimProbeFailure twins |
| Job kind for AppX remove | keep **`appx.safetyNet`** (kind string) | rename job **id** `keepflag.appx.safetyNet` → `debloat.appx.safetyNet` |
| Error codes | `debloat.preset.unknown` etc. | `keepflag.preset.unknown` |

### Explicitly out of scope (would add or churn without net delete)

- Splitting `SessionEnvironment` into mode-specific records (adds types)
- Unifying Orchestrator/Provisioning `BundleFile` into a shared project (adds assembly)
- Merging servicing `*.ps1` kernels (breaks 1:1 opcode map)
- Deleting Provisioning `I*` ports that have test fakes
- Catalog file merges that only reshuffle lines

### Target net

| Pass | Estimate |
|------|----------|
| Tasks 1–6 (vocab + deletes) | **−80…−150** LOC + fewer files + clearer docs |
| Task 7 (Apply glue) only if net-negative | **−30…−50** or **skip** |
| NuGet | **0** |

---

## File map (who owns what)

| Path | Role after this plan |
|------|----------------------|
| `CONTEXT.md` | Language table: Debloat canonical; Shell = Winlogon only |
| `docs/DESIGN.md` | Invariant 4 says Debloat, not Keep-flag |
| `docs/design/DEBLOAT.md` | Was KEEPFLAG.md — same remove-list design, Debloat name |
| `docs/design/KEEPFLAG.md` | Stub redirect → DEBLOAT.md (or delete if links updated) |
| `docs/decisions/ADR-005-*.md` | One-line naming supersession → Debloat |
| `src/WinMint.Orchestrator/DebloatPresets.cs` | Was KeepFlagPresets.cs |
| `src/WinMint.Orchestrator/BuildArtifacts.cs` | `Failure` replaces `PlanFailure` |
| `src/WinMint.Orchestrator/ImageServicing.Types.cs` | Use `Failure`; delete `ServicingFailure` |
| `src/WinMint.Orchestrator/DocumentErrors.cs` | Keep `DocumentError`; delete `DocumentErrors` wrapper |
| `src/WinMint.Orchestrator/Profile.cs` | Nest `PoliciesProfile`; inline `AccountModeWire` const |
| `src/WinMint.Provisioning/ProvisioningSession.Types.cs` | `string SupervisorShellPath`; no `SupervisorIdentity` |
| `src/WinMint.Wizard/ViewModels/WizardViewModel.cs` | Was WizardShellViewModel |
| `src/WinMint.Cli/Program.cs` + `WizardBuild.cs` | Shared load+plan only if Task 7 nets delete |

---

### Task 1: Canonical Debloat vocabulary (docs + types + wire ids)

**Files:**
- Modify: `CONTEXT.md` (Language section)
- Modify: `docs/DESIGN.md` (invariant 4 + any Keep-flag cross-refs)
- Create: `docs/design/DEBLOAT.md` (content from KEEPFLAG.md, vocabulary updated)
- Modify or stub: `docs/design/KEEPFLAG.md` → pointer to DEBLOAT.md
- Modify: `docs/DESIGN.md` cross-link KEEPFLAG → DEBLOAT
- Modify: `docs/decisions/ADR-005-keep-flag-matrix.md` (add **Naming supersession** section only)
- Modify: `docs/decisions/ADR-006-post-keepflag-sequencing.md`, `ADR-007-cdm-not-primary.md` — update living links/phrases to Debloat where they teach vocabulary (not historical ticket titles)
- Rename/modify: `src/WinMint.Orchestrator/KeepFlagPresets.cs` → `DebloatPresets.cs` (`DebloatPresets`, `DebloatExpansion`)
- Modify: all call sites (`WizardSession`, `WizardShellViewModel` / later WizardViewModel, tests, CapabilityCatalog comments)
- Modify: `BuildPlan.cs` job id `keepflag.appx.safetyNet` → `debloat.appx.safetyNet`
- Modify: error codes `keepflag.preset.unknown` → `debloat.preset.unknown`
- Rename test files optionally: `KeepFlag*Tests.cs` → `Debloat*Tests.cs` (same session if cheap; else leave filenames for a follow-up — types must rename now)

**Interfaces:**
- Consumes: existing Profile `debloat.*` / `DebloatMode`
- Produces: `DebloatPresets.TryExpand(string) → Result<DebloatExpansion, Failure>` (Failure may still be PlanFailure until Task 3 — use whatever failure type exists at time of task; Task 3 renames)

- [ ] **Step 1: Lock CONTEXT Language**

In `CONTEXT.md` Language section, add/replace:

```markdown
**Debloat** — Remove-list posture for AppX / capabilities / optional features. Profile fields are `debloat.*`. Host presets (`recommended`, Acceptance, empty) expand to lists; never write preset names into JSON.  
_Avoid_: Keep-flag (retired name); keep-list polarity; BCU; CDM as primary; Profile preset names
```

Add under Shell / Supervisor (clarify collision):

```markdown
**Shell** — Winlogon replacement during Provisioning tenure only.  
_Avoid_: calling Wizard UI chrome “Shell”
```

- [ ] **Step 2: DESIGN invariant 4**

Change:

```markdown
4. Keep-flag: remove-list only; no Profile preset names in JSON; CDM not primary
```

to:

```markdown
4. Debloat: remove-list only; no Profile preset names in JSON; CDM not primary
```

Update the KEEPFLAG link to DEBLOAT.

- [ ] **Step 3: KEEPFLAG.md → DEBLOAT.md**

Copy content; replace living “Keep-flag” / `KeepFlagPresets` with Debloat / `DebloatPresets`. Leave a short KEEPFLAG.md stub:

```markdown
# Keep-flag (retired name)

**Renamed to [DEBLOAT](DEBLOAT.md).** Same remove-list design; Profile JSON was always `debloat.*`.
```

- [ ] **Step 4: ADR-005 naming supersession**

Append (do not rewrite Decision body):

```markdown
### Naming supersession (2026-08-10)

Living vocabulary is **Debloat** (Profile `debloat.*`, host `DebloatPresets`). “Keep-flag” in this ADR’s title is historical. Policy §§1–2, 4–7 unchanged.
```

- [ ] **Step 5: Rename code types**

```csharp
// DebloatPresets.cs (was KeepFlagPresets.cs)
public static class DebloatPresets
{
    public const string Empty = "empty";
    public const string Acceptance = "acceptance";
    public const string Recommended = "recommended";

    public static Result<DebloatExpansion, PlanFailure> TryExpand(string name) { /* same logic; codes debloat.preset.unknown */ }
}

public sealed record DebloatExpansion(
    IReadOnlyList<string> RemoveProvisionedAppx,
    IReadOnlyList<string> RemoveCapabilities,
    IReadOnlyList<string> DisableOptionalFeatures)
{
    public static DebloatExpansion Empty { get; } = new([], [], []);
}
```

Job emission in `BuildPlan.cs`:

```csharp
jobList.Add(new JobDescriptor("debloat.appx.safetyNet", "appx.safetyNet"));
```

Kind string stays `"appx.safetyNet"`.

- [ ] **Step 6: Update tests + run**

Update asserts on job **Id** and error codes. Run:

```powershell
just check
```

Expected: PASS. If only subset: `dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~Debloat|FullyQualifiedName~KeepFlag|FullyQualifiedName~OnlineDebloat|FullyQualifiedName~Preset"`

- [ ] **Step 7: Commit (when user asks)**

```
docs(vocab): canonical Debloat; retire Keep-flag living name
```

---

### Task 2: Delete speculative SessionPolicy fields from design doc

**Files:**
- Modify: `docs/design/PROVISIONINGSESSION.md` (SessionPolicy sketch + table)
- Modify (comment only if needed): `src/WinMint.Provisioning/GdiSplashPresenter.cs` — keep “2.0 s first paint” as prose, drop type names that imply knobs

**Interfaces:**
- Consumes: real `SessionPolicy` in `ProvisioningSession.Types.cs` (5 TimeSpans only)
- Produces: design doc matching code

- [ ] **Step 1: Align doc sketch to code**

Replace design `SessionPolicy` with:

```csharp
public sealed record SessionPolicy(
    TimeSpan WallClockTimeout,
    TimeSpan SettleDeadline,
    TimeSpan SettlePollInterval,
    TimeSpan FailedDwell,
    TimeSpan StaleTenureThreshold);
```

Delete `FirstPaintBudget`, `InputLock` / `InputLockMode` from the design sketch and defaults table. Move first-paint 2.0 s into Splash / S4 acceptance prose if needed (not a SessionPolicy field).

- [ ] **Step 2: Grep confirm**

```powershell
rg "FirstPaintBudget|InputLock" docs/design src
```

Expected: only harness assert param (`tools/vm/Assert-SmokeEvidence.ps1`) and optional GDI comment — not SessionPolicy.

- [ ] **Step 3: Commit (when user asks)**

```
docs(provisioning): drop phantom FirstPaintBudget/InputLock from SessionPolicy
```

---

### Task 3: One Failure type (delete twins)

**Files:**
- Modify: `src/WinMint.Orchestrator/BuildArtifacts.cs` — rename `PlanFailure` → `Failure`
- Modify: `src/WinMint.Orchestrator/ImageServicing.Types.cs` — delete `ServicingFailure`; use `Failure`
- Modify: `src/WinMint.Wizard/SourceWimProbe.cs` — delete `WimProbeFailure`; use `Failure` (or map at boundary without a new type)
- Modify: every `PlanFailure` / `ServicingFailure` / `WimProbeFailure` reference in src + tests

**Interfaces:**
- Produces: `public sealed record Failure(string Code, string Message);`
- `BuildPlan.Plan` → `Result<BuildArtifacts, Failure>`
- `ImageServicing.Apply` → `Result<ImageEvidence, Failure>`
- `DebloatPresets.TryExpand` → `Result<DebloatExpansion, Failure>`

- [ ] **Step 1: Introduce Failure; alias temporarily only if compile pain**

Prefer mechanical rename — **no** `using PlanFailure = Failure` left behind.

```csharp
public sealed record Failure(string Code, string Message);
```

Delete:

```csharp
// DELETE
public sealed record PlanFailure(string Code, string Message);
public sealed record ServicingFailure(string Code, string Message);
internal sealed record WimProbeFailure(string Code, string Message);
```

- [ ] **Step 2: Fix compile errors across solution**

```powershell
dotnet build WinMint.sln
```

Expected: 0 errors.

- [ ] **Step 3: just check**

```powershell
just check
```

- [ ] **Step 4: Commit (when user asks)**

```
refactor: single Failure record; delete Plan/Servicing/WimProbe twins
```

---

### Task 4: Delete DocumentErrors wrapper + SupervisorIdentity

**Files:**
- Modify: `src/WinMint.Orchestrator/DocumentErrors.cs` — keep `DocumentError`; delete `DocumentErrors`
- Modify: `BuildPlan.TryParseProfile`, `ProfileFile.TryLoad`, Wizard/Cli/tests — `Result<Profile, IReadOnlyList<DocumentError>>`
- Modify: `ProvisioningSession.Types.cs` — replace `SupervisorIdentity Supervisor` with `string SupervisorShellPath`
- Modify: `BundleLoader.cs`, `ProvisioningSession.cs`, test fakes (`UnlockTimeoutTests`, `MachineSetupTests`, `DmaSettleTests`, `ShellTenureTests`, `ProvisioningSessionTestFakes`)

**Interfaces:**
- Produces: `Result<Profile, IReadOnlyList<DocumentError>>`
- Produces: `ProvisioningBundle(..., string SupervisorShellPath, ...)`

- [ ] **Step 1: Flatten DocumentErrors**

```csharp
// DocumentErrors.cs — only:
public sealed record DocumentError(string Code, string Message, string? Path = null);

// Call sites:
return Result.Fail<Profile, IReadOnlyList<DocumentError>>([new DocumentError(...)]);
// was: new DocumentErrors([...])
```

Helpers that returned `DocumentErrors` become `IReadOnlyList<DocumentError>` or `DocumentError[]`.

- [ ] **Step 2: Flatten SupervisorIdentity**

```csharp
// DELETE: public sealed record SupervisorIdentity(string ShellPath);

// Bundle construction:
SupervisorShellPath: dto.SupervisorPath,

// Tenure check:
string expectedShell = scrubbedView.SupervisorShellPath;
```

- [ ] **Step 3: just check**

- [ ] **Step 4: Commit (when user asks)**

```
refactor: drop DocumentErrors + SupervisorIdentity wrappers
```

---

### Task 5: Fold micro-files (delete files, nest types)

**Files:**
- Modify: `Profile.cs` — move `PoliciesProfile` here; delete `PoliciesProfile.cs`
- Modify: `Profile.cs` — replace `AccountModeWire` class with `AccountProfile.LocalAutoLogonMode = "localAutoLogon"` (or const on `BuildPlan`)
- Modify: `ImageServicing.cs` — private helpers from `PwshHostGuard`; delete `PwshHostGuard.cs`
- Modify: `BuildPlan.cs` — move `WingetImportBuilder` to `private static` helpers; delete `WingetImportBuilder.cs`
- Modify: `PackageCatalog.cs` — move `PackageCatalogValidator` methods; delete `PackageCatalogValidator.cs`
- Update: project file compiles (SDK-style — delete files enough)

**Rule:** Deletion of one-caller files wins — fold all listed micro-files; navigability is not a skip criterion.

- [ ] **Step 1: PoliciesProfile nest**

Move record into `Profile.cs`; delete file; build.

- [ ] **Step 2: AccountModeWire → const**

```csharp
public sealed record AccountProfile(...)
{
    public const string LocalAutoLogonMode = "localAutoLogon";
}
```

Replace `AccountModeWire.LocalAutoLogon` → `AccountProfile.LocalAutoLogonMode`. Delete `AccountModeWire` class.

- [ ] **Step 3: PwshHostGuard + PackageCatalogValidator folds**

Inline; delete files.

- [ ] **Step 4: WingetImportBuilder fold**

Move `WingetImportBuilder` to `private static` helpers in `BuildPlan.cs`; delete `WingetImportBuilder.cs`.

- [ ] **Step 5: just check**

- [ ] **Step 6: Commit (when user asks)**

```
refactor: fold micro-types; delete wrapper files
```

---

### Task 6: Rename WizardShellViewModel (Shell vocabulary)

**Files:**
- Rename: `WizardShellViewModel.cs` → `WizardViewModel.cs` (class `WizardViewModel`)
- Modify: XAML / `App.axaml.cs` / `MainWindow` bindings that reference the type
- Grep: `WizardShell`

**Interfaces:**
- Produces: `WizardViewModel` — same MVVM surface

- [ ] **Step 1: Rename type + file**

- [ ] **Step 2: just check** (Wizard project + tests)

- [ ] **Step 3: Commit (when user asks)**

```
refactor(wizard): WizardViewModel — Shell means Winlogon only
```

---

### Task 7: Share load+plan path (only if net-negative)

**Files:**
- Modify: `src/WinMint.Orchestrator/ProfileFile.cs` or `BuildPlan.cs` — **one** method:

```csharp
public static Result<BuildArtifacts, Failure> TryLoadAndPlan(string profilePath, RunOptions? run = null)
{
    Result<Profile, IReadOnlyList<DocumentError>> loaded = ProfileFile.TryLoad(profilePath);
    if (!loaded.IsOk)
    {
        DocumentError first = loaded.Error[0];
        return Result.Fail<BuildArtifacts, Failure>(new Failure(first.Code, first.Message));
    }

    return BuildPlan.Plan(loaded.Value, run);
}
```

**Caution:** Collapsing `DocumentError[]` → single `Failure` loses multi-error listing for Cli. Prefer:

```csharp
public static Result<(Profile Profile, BuildArtifacts Artifacts), IReadOnlyList<DocumentError>> ...
// NO — that adds tuples and complexity.
```

**Better deletion approach:** Do **not** add `TryLoadAndPlan` if Cli must keep multi-error print and Wizard wants single-string. Instead:

- Delete only duplicated **comments**/dead branches
- Or extract nothing: **SKIP this task** and record “Apply glue left intentional — hosts need different error surfacing”

- [ ] **Step 1: Diff Cli `TryLoadArtifacts` vs WizardBuild mid-section**

If shared helper forces worse error UX or extra adapters → **mark task skipped**, no code.

- [ ] **Step 2: If shared path is clearly shorter**

Implement one Orchestrator helper that returns `Result<BuildArtifacts, Failure>` **and** a separate parse path remains for multi-error Cli — only delete Wizard duplication (Wizard already collapses errors). Net: WizardBuild shrinks; Cli unchanged. Still no new project.

- [ ] **Step 3: just check**

- [ ] **Step 4: Commit or skip note**

```
refactor: Wizard uses shared Plan load helper
```
or document skip in progress notes.

---

### Task 8: Verify + audit canvas note

- [ ] **Step 1: Full gate**

```powershell
just check
```

- [ ] **Step 2: Grep living KeepFlag / Keep-flag**

```powershell
rg -i "KeepFlag|keep-flag|Keep-flag" src docs/DESIGN.md docs/design CONTEXT.md --glob '!**/ADR-*' --glob '!**/KEEPFLAG.md'
```

Expected: no living hits outside ADR history + KEEPFLAG stub + optional old plan archives.

- [ ] **Step 3: Line / file tally**

Count deleted files and approximate LOC removed; update progress if using SDD notes.

- [ ] **Step 4: Do not claim “complexity fixed” without the greps + `just check` green.

---

## Self-review

1. **Spec coverage:** Audit top-5 → Tasks 1 (vocab), 3 (failures), 4 (wrappers), 5 (micro-folds), 7 (Apply, optional). SessionEnvironment split explicitly rejected. Twin BundleFile left (would need Contracts).
2. **Placeholders:** None intentional; Task 7 has explicit skip criteria.
3. **Type consistency:** Task 1 may still say `PlanFailure` until Task 3 renames to `Failure` — implementers running Task 1 alone use current name; Task 3 is mechanical replace.
4. **Vocabulary:** Debloat wins; design docs change; ADRs get supersession notes only.

---

## Execution handoff

Plan saved to `docs/superpowers/plans/2026-08-10-complexity-deletion-pass.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — this session, executing-plans style with checkpoints  

Which approach?
