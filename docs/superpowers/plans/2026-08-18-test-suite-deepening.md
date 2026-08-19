# Test-suite deepening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `just check` assert through existing module interfaces so Smoke wait-policy, freshness, WinPE apply defects, policy JSON, and prepared-media audit are not duplicated as source greps or InternalsVisibleTo peeks.

**Architecture:** One plan, six review cards from `architecture-review-20260818-1418.html`. Deepen by sharing or deleting — do not add a Hyper-V executor, an `IImageServicing` port, or Smoke to `just check`. Speculative cards are in scope: C5 types the prepared-media projection on `ImageEvidence`; C6 records a Don’t and keeps firmware greps.

**Tech Stack:** pwsh 7.6+, xUnit on net11.0, existing `tests/contract/Test-*.ps1` discovery, `just check`.

**Review:** [architecture-review-20260818-1418.html](file:///C:/Users/yanai/AppData/Local/Temp/architecture-review-20260818-1418.html)  
**Living rules:** [TDD.md](../../TDD.md), [DESIGN.md](../../DESIGN.md), ADR-004, ADR-009.

## Global Constraints

- pwsh 7.6+ (`#requires -Version 7.6`).
- `just check` stays free of Hyper-V and of a Source ISO.
- Do not invent a Hyper-V settle/executor path. Do not add `IImageServicing`. Fake `IElevatedPlanRunner` already exists — do not add a second one.
- Elevate only Servicing `pwsh -File`. Do not call `PwshElevatedPlanRunner.ExecuteAsync` from tests (UAC / DISM).
- Evidence JSON is a projection, not a control plane. S4/S5 harness tests may still read evidence files.
- `Get-SmokeWatchVerdict` never takes a PID list. Watchers must not `Stop-VM` / `Remove-VM`.
- Commit style: `test(scope):` · `fix(scope):` · `docs:` — only when executing this plan (maintainer asked for the plan here, not a commit yet).
- Solo — no PRs.

## File structure

| Path | Responsibility |
| --- | --- |
| Modify `tools/vm/SmokeStatus.ps1` | `Get-SmokeWatchVerdict` stays the wait-policy interface. Notes: waiter throws on `empty-vhd`; watchers still report-only. |
| Modify `tools/vm/Invoke-Smoke.ps1` | Wait loop calls `Get-SmokeWatchVerdict` and throws `EMPTY_VHD:` when the verdict is `empty-vhd`. Keep Stopwatch for elapsed. |
| Modify `tests/contract/Test-SmokeStatus.ps1` | Require `Get-SmokeWatchVerdict` in Invoke-Smoke; drop the tautology that only greps `EMPTY_VHD` without the call. |
| Modify `src/WinMint.Orchestrator/ImageServicing.cs` | `CheckPublishedBinaryFreshness` is the freshness interface; `FindSourceNewerThan` stays implementation. |
| Modify `tests/WinMint.Tests/SupervisorFreshnessTests.cs` | Drive temp trees through `CheckPublishedBinaryFreshness`. |
| Modify `src/WinMint.Orchestrator/PwshElevatedPlanRunner.cs` | `RefuseStoreMsixPwsh` is the pre-elevation host check; `ExecuteAsync` calls it then freshness then process start. |
| Modify `tests/WinMint.Tests/PwshElevatedPlanRunnerTests.cs` | Store-MSIX through `RefuseStoreMsixPwsh`. Keep `FirstNonStorePwsh`. |
| Modify `tests/WinMint.Tests/HostReviewCopyTests.cs` | Drop `PlanDiff.FriendlyRemoveNames` facts; cover names through `HostReview.WhatsIncluded`. |
| Modify `tests/WinMint.Tests/WinPeApplyPlanTests.cs` | Delete Patch-Boot script-text facts that `Test-DiskGuard` already executes. |
| Delete `tests/contract/Test-PolicyPayloadJson.ps1` | Round-trip already lives on `ImageServicing.Apply`. |
| Modify `src/WinMint.Orchestrator/ImageServicing.Types.cs` | `ImageEvidence.PreparedMediaFields`. |
| Modify `src/WinMint.Orchestrator/ImageServicing.Evidence.cs` | Fill `PreparedMediaFields` from the audit; do not put those keys on `Digests`. |
| Modify `tests/WinMint.Tests/ImageServicingApplyTests.cs` | Assert `PreparedMediaFields`, not `evidence.json`. |
| Modify `docs/TDD.md` | Waiter shares wait-policy; freshness through `CheckPublishedBinaryFreshness`; no Hyper-V adapters for disk-boot four-liners. |
| Unchanged | `Get-SmokePreferDiskBootDecision`, `Get-SmokeEjectDvdDecision`, wait-loop `Running { Prefer-DiskBoot }` grep, `Set-VMDvdDrive` slice, `Test-DiskGuard.ps1`, `FormatBusyLabel` presenter tests, S4/S5 evidence-assert tests. |

---

### Task 1: Waiter throws on `Get-SmokeWatchVerdict` (Strong / C1)

**Files:**
- Modify: `tests/contract/Test-SmokeStatus.ps1` (source-contract near the top)
- Modify: `tools/vm/Invoke-Smoke.ps1` (wait loop after VHD size / Stopwatch)
- Modify: `tools/vm/SmokeStatus.ps1` (`Get-SmokeWatchVerdict` comment block)
- Modify: `docs/TDD.md` (S4 paragraph)

**Interfaces:**
- Consumes: `Get-SmokeWatchVerdict` — params `Phase` (string, mandatory), `VmState` (string, default `''`), `VhdFileSizeMB` (int, default 0), `StatusAgeSeconds` (int, default 0), `EmptyVhdRunningSeconds` (int, default 0), `EmptyVhdFailAfterSeconds` (int, default 480), `HarnessStaleAfterSeconds` (int, default 120). Returns `done` | `continue` | `empty-vhd` | `harness-stale`.
- Produces: Invoke-Smoke wait loop calls `Get-SmokeWatchVerdict` with live phase, VM state, VHD MB, empty-VHD Stopwatch seconds, and `-EmptyVhdFailAfterSeconds ([int]($EmptyVhdMinutes * 60))`. On `empty-vhd`, throw `EMPTY_VHD: WinPE has not applied (VHD FileSize still under 1GB) for ${EmptyVhdMinutes} minutes after Running.` Waiter must not pass `StatusAgeSeconds` (leave default 0) and must not throw on `harness-stale`. Stall remains a separate Stopwatch throw (`STALL_SUSPECT`).

- [ ] **Step 1: Fail the source-contract if Invoke-Smoke never calls the verdict**

In `tests/contract/Test-SmokeStatus.ps1`, replace the `EMPTY_VHD` needle-only check with a call-site check. Keep the `EMPTY_VHD` throw-prefix so operator copy stays:

```powershell
if ($smoke -notmatch 'Get-SmokeWatchVerdict') { throw 'Invoke-Smoke wait loop must call Get-SmokeWatchVerdict' }
if ($smoke -notmatch 'EMPTY_VHD:') { throw 'empty-VHD throw prefix missing (operator copy)' }
if ($smoke -notmatch '\[Diagnostics\.Stopwatch\]') { throw 'stall/wall/empty-vhd must use Stopwatch, not UtcNow deadlines' }
```

Do not remove the existing `Enable-VMEventing` / no-PID greps or the `Get-SmokeWatchVerdict` table (guest-up 17 GB `continue`, Running 36 MB at 480s `empty-vhd`).

- [ ] **Step 2: Run it to verify it fails**

```powershell
pwsh -NoProfile -File tests/contract/Test-SmokeStatus.ps1
```

Expected: FAIL with `Invoke-Smoke wait loop must call Get-SmokeWatchVerdict`.

- [ ] **Step 3: Call the verdict from the wait loop**

Keep the empty-VHD Stopwatch start/stop block (elapsed is still QPC). Remove only the inner `if ($script:emptyVhdSw.Elapsed.TotalMinutes -ge $EmptyVhdMinutes) { throw "EMPTY_VHD: ..." }`.

After `$phase = Resolve-SmokePhase ...` and `Write-SmokeStatus ...`, add:

```powershell
        $emptySecs = 0
        if ($null -ne $script:emptyVhdSw) {
            $emptySecs = [int]$script:emptyVhdSw.Elapsed.TotalSeconds
        }
        $verdict = Get-SmokeWatchVerdict -Phase $phase -VmState ([string]$vm.State) `
            -VhdFileSizeMB ([int][math]::Round($vhdBytes / 1MB)) `
            -EmptyVhdRunningSeconds $emptySecs `
            -EmptyVhdFailAfterSeconds ([int]($EmptyVhdMinutes * 60))
        if ($verdict -eq 'empty-vhd') {
            throw "EMPTY_VHD: WinPE has not applied (VHD FileSize still under 1GB) for ${EmptyVhdMinutes} minutes after Running."
        }
```

Update `Get-SmokeWatchVerdict` notes to: waiter throws on `empty-vhd`; watchers must not `Stop-VM` / `Remove-VM`; `harness-stale` stays watch-only.

In `docs/TDD.md` S4, add that Invoke-Smoke throws from `Get-SmokeWatchVerdict`, not a second empty-VHD `if`.

- [ ] **Step 4: Run the contract test**

```powershell
pwsh -NoProfile -File tests/contract/Test-SmokeStatus.ps1
```

Expected: `Test-SmokeStatus ok`, exit 0. Existing verdict table still passes (apply + tiny VHD + 480s is `continue` because phase `apply` short-circuits).

- [ ] **Step 5: Commit**

```bash
git add tests/contract/Test-SmokeStatus.ps1 tools/vm/Invoke-Smoke.ps1 tools/vm/SmokeStatus.ps1 docs/TDD.md
git commit -m "test(smoke): waiter throws on Get-SmokeWatchVerdict empty-vhd"
```

---

### Task 2: Freshness and store-MSIX through public checks (Worth exploring / C2)

**Files:**
- Modify: `tests/WinMint.Tests/SupervisorFreshnessTests.cs`
- Modify: `src/WinMint.Orchestrator/ImageServicing.cs` (`CheckSupervisorFreshness` / `CheckWinPeApplyFreshness` / new `CheckPublishedBinaryFreshness`; keep `FindSourceNewerThan` as implementation)
- Modify: `tests/WinMint.Tests/PwshElevatedPlanRunnerTests.cs`
- Modify: `src/WinMint.Orchestrator/PwshElevatedPlanRunner.cs` (`ExecuteAsync` prefix)
- Modify: `tests/WinMint.Tests/HostReviewCopyTests.cs`
- Modify: `docs/TDD.md` (S2 / anti-patterns)

**Interfaces:**
- Consumes: existing `Failure? CheckSupervisorFreshness()` and `Failure? CheckWinPeApplyFreshness()` (zero-arg, real ToolkitRoot). Existing `IsStoreMsixPwsh` / `FirstNonStorePwsh`.
- Produces:
  - `internal static Failure? CheckPublishedBinaryFreshness(string? publishedExe, IEnumerable<string?> sourceRoots, string code, string publishedLabel, string remedy)` — null when publish is missing, source is missing, or no `*.cs` (excluding `obj`/`bin`) is newer than the exe and `<= UtcNow`. Otherwise `Failure` with `code` and message `$"Published {publishedLabel} predates '{stalePath}'. An ISO built now would ship guest code that no longer matches this tree. Run: {remedy}"`. `CheckSupervisorFreshness` becomes: published via `FindPublishedSupervisor()`, roots `WinMint.Provisioning` + `WinMint.Contracts`, code `hostCompile.supervisor.stale`, label `Supervisor`, remedy `just publish-provisioning`. `CheckWinPeApplyFreshness` becomes: published via `FindPublishedWinPeApply()`, root `WinMint.WinPeApply`, code `hostCompile.winPeApply.stale`, label `WinMintApply`, same remedy.
  - `internal static Failure? RefuseStoreMsixPwsh(string? pwshPath)` — same `Failure("servicing.pwsh.storeMsix", ...)` as today’s `ExecuteAsync` when path is null or store MSIX. `ExecuteAsync` calls this, then `CheckSupervisorFreshness()`, then `CheckWinPeApplyFreshness()`, then starts pwsh. Tests must not call `ExecuteAsync`.

- [ ] **Step 1: Write failing freshness tests on `CheckPublishedBinaryFreshness`**

Replace every `ImageServicing.FindSourceNewerThan(...)` call in `SupervisorFreshnessTests.cs` with `CheckPublishedBinaryFreshness`. Keep the same temp-tree helpers (`Publish`, `Source`, `SourceRoot`). Exact facts:

```csharp
[Fact]
public void Source_newer_than_the_publish_is_reported()
{
    string exe = Publish(at: new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc));
    string source = Source("Program.cs", at: new DateTime(2026, 1, 2, 0, 0, 0, DateTimeKind.Utc));

    Failure? stale = ImageServicing.CheckPublishedBinaryFreshness(
        exe, [SourceRoot], "hostCompile.supervisor.stale", "Supervisor", "just publish-provisioning");

    Assert.NotNull(stale);
    Assert.Equal("hostCompile.supervisor.stale", stale.Code);
    Assert.Contains(source, stale.Message, StringComparison.Ordinal);
    Assert.Contains("just publish-provisioning", stale.Message, StringComparison.Ordinal);
}

[Fact]
public void Publish_newer_than_source_is_current()
{
    string exe = Publish(at: new DateTime(2026, 1, 2, 0, 0, 0, DateTimeKind.Utc));
    _ = Source("Program.cs", at: new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc));

    Assert.Null(ImageServicing.CheckPublishedBinaryFreshness(
        exe, [SourceRoot], "hostCompile.supervisor.stale", "Supervisor", "just publish-provisioning"));
}

[Fact]
public void Source_mtime_in_the_future_is_clock_skew_not_stale()
{
    DateTime now = DateTime.UtcNow;
    string exe = Publish(at: now.AddMinutes(-5));
    _ = Source("Program.cs", at: now.AddHours(2));

    Assert.Null(ImageServicing.CheckPublishedBinaryFreshness(
        exe, [SourceRoot], "hostCompile.supervisor.stale", "Supervisor", "just publish-provisioning"));
}

[Fact]
public void Build_output_is_not_mistaken_for_source()
{
    string exe = Publish(at: new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc));
    _ = Source(Path.Combine("obj", "Generated.cs"), at: new DateTime(2026, 1, 2, 0, 0, 0, DateTimeKind.Utc));

    Assert.Null(ImageServicing.CheckPublishedBinaryFreshness(
        exe, [SourceRoot], "hostCompile.supervisor.stale", "Supervisor", "just publish-provisioning"));
}

[Fact]
public void Absent_source_cannot_be_checked_and_must_not_block()
{
    string exe = Publish(at: new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc));

    Assert.Null(ImageServicing.CheckPublishedBinaryFreshness(
        exe, [Path.Combine(_root, "no-such-src")], "hostCompile.supervisor.stale", "Supervisor", "just publish-provisioning"));
}

[Fact]
public void Missing_publish_cannot_be_checked_and_must_not_block()
{
    Assert.Null(ImageServicing.CheckPublishedBinaryFreshness(
        null, [SourceRoot], "hostCompile.supervisor.stale", "Supervisor", "just publish-provisioning"));
}
```

Do not call `FindSourceNewerThan` from tests after this change.

- [ ] **Step 2: Run to verify it fails**

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~SupervisorFreshnessTests" -- --filter-not-trait "Category=S4" --filter-not-trait "Category=S5"
```

Expected: FAIL — `CheckPublishedBinaryFreshness` does not exist.

- [ ] **Step 3: Implement `CheckPublishedBinaryFreshness` and rewrite the zero-arg wrappers**

In `ImageServicing.cs`:

```csharp
internal static Failure? CheckPublishedBinaryFreshness(
    string? publishedExe,
    IEnumerable<string?> sourceRoots,
    string code,
    string publishedLabel,
    string remedy)
{
    if (publishedExe is null)
    {
        return null;
    }

    string? staleSince = sourceRoots
        .Select(root => FindSourceNewerThan(publishedExe, root))
        .FirstOrDefault(static hit => hit is not null);

    return staleSince is null
        ? null
        : new Failure(
            code,
            $"Published {publishedLabel} predates '{staleSince}'. An ISO built now would ship guest code that no longer matches this tree. Run: {remedy}");
}
```

`CheckSupervisorFreshness` / `CheckWinPeApplyFreshness` call this helper. Leave `FindSourceNewerThan` as `internal static` implementation (mtime, skew, `obj`/`bin` skip).

- [ ] **Step 4: Run freshness tests**

Same `dotnet test` filter as Step 2.

Expected: PASS.

- [ ] **Step 5: Write failing store-MSIX tests on `RefuseStoreMsixPwsh`**

Add to `PwshElevatedPlanRunnerTests.cs` (keep `FirstNonStorePwsh` facts):

```csharp
[Fact]
public void Store_msix_pwsh_is_refused_before_elevation()
{
    Failure? refused = PwshElevatedPlanRunner.RefuseStoreMsixPwsh(
        @"C:\Program Files\WindowsApps\Microsoft.PowerShell_7.4.0.0_arm64__8wekyb3d8bbwe\pwsh.exe");
    Assert.NotNull(refused);
    Assert.Equal("servicing.pwsh.storeMsix", refused.Code);
}

[Fact]
public void Msi_pwsh_is_not_refused_as_store_msix()
{
    Assert.Null(PwshElevatedPlanRunner.RefuseStoreMsixPwsh(
        @"C:\Program Files\PowerShell\7\pwsh.exe"));
}
```

Rewrite `Pwsh_store_path_detected` to call `RefuseStoreMsixPwsh` / keep `IsStoreMsixPwsh` only if `RefuseStoreMsixPwsh` uses it internally — tests should not need both. Prefer one fact per WindowsApps shape through `RefuseStoreMsixPwsh` (WindowsApps package dir, WindowsApps alias, MSI Program Files).

- [ ] **Step 6: Run to verify it fails**

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~PwshElevatedPlanRunnerTests"
```

Expected: FAIL — `RefuseStoreMsixPwsh` does not exist.

- [ ] **Step 7: Implement `RefuseStoreMsixPwsh` and call it from `ExecuteAsync`**

```csharp
internal static Failure? RefuseStoreMsixPwsh(string? pwshPath)
{
    if (pwshPath is null || IsStoreMsixPwsh(pwshPath))
    {
        return new Failure(
            "servicing.pwsh.storeMsix",
            "Host pwsh is WindowsApps MSIX (winget Microsoft.PowerShell defaults to msix). DISM needs GitHub PowerShell-*-win-arm64.msi (or win-x64) under Program Files\\PowerShell\\7.");
    }

    return null;
}
```

`ExecuteAsync` after `ResolvePwshPath()`:

```csharp
if (RefuseStoreMsixPwsh(pwshPath) is { } storeMsix)
{
    return Result.Fail<ElevatedRunOk, Failure>(storeMsix);
}
```

Then the existing `CheckSupervisorFreshness` / `CheckWinPeApplyFreshness` calls. Do not start a process in tests.

- [ ] **Step 8: Fold `FriendlyRemoveNames_*` into `WhatsIncluded`**

Delete `FriendlyRemoveNames_maps_known_recommended_appx_ids` and `FriendlyRemoveNames_falls_back_to_last_segment_for_unknown_ids`. Extend `WhatsIncluded_joins_friendly_names` (same `HostCompile.PlanDocument` + `Review with { RemoveProvisionedAppx = ... }` pattern already in that file):

```csharp
[Fact]
public void WhatsIncluded_joins_friendly_names()
{
    Result<HostPlan, HostComposeError> planned = HostCompile.PlanDocument(Lab());
    Assert.True(planned.IsOk);
    Assert.Equal(
        "Bing News · UnknownApp",
        (planned.Value.Review with
        {
            RemoveProvisionedAppx = ["Microsoft.BingNews", "Contoso.UnknownApp"],
        }).WhatsIncluded);
}
```

Keep `FormatBusyLabel_*` in `ApplyProgressTests` — that is the Wizard busy-label presenter (TDD allows status → presenter). Do not drive it through navigation.

In `docs/TDD.md` S2: freshness tests go through `CheckPublishedBinaryFreshness`; store-MSIX through `RefuseStoreMsixPwsh`; do not call `ExecuteAsync` from `just check`.

- [ ] **Step 9: Run the C# tests for this task**

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~SupervisorFreshnessTests|FullyQualifiedName~PwshElevatedPlanRunnerTests|FullyQualifiedName~HostReviewCopyTests"
```

Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add src/WinMint.Orchestrator/ImageServicing.cs src/WinMint.Orchestrator/PwshElevatedPlanRunner.cs tests/WinMint.Tests/SupervisorFreshnessTests.cs tests/WinMint.Tests/PwshElevatedPlanRunnerTests.cs tests/WinMint.Tests/HostReviewCopyTests.cs docs/TDD.md
git commit -m "test(servicing): freshness and store-MSIX through published-binary checks"
```

---

### Task 3: Delete C# Patch-Boot greps that DiskGuard already runs (Worth exploring / C3)

**Files:**
- Modify: `tests/WinMint.Tests/WinPeApplyPlanTests.cs`
- Unchanged: `tests/contract/Test-DiskGuard.ps1`, `WinPeApplyPlanTests.Apply_materializes_winpe_opcode_params`, `WinPeApplyPlanTests.Plan_emits_oobe_unattend_stages_without_windowsPE`, `WinPeApplyPlanTests.BuildIso_script_does_not_finalize_plan_evidence`

**Interfaces:**
- Consumes: `Get-WinPeApplyDefect` (executed by `Test-DiskGuard.ps1`); `ImageServicing.ApplyAsync` winpe opcode params (already tested).
- Produces: `WinPeApplyPlanTests` no longer reads `Patch-BootWimApply.ps1` / `LaunchApply.cmd` / `Assert-ApplyEvidence.ps1` as source needles for apply-lane / all-index policy.

- [ ] **Step 1: Delete the two script-text facts**

Remove `PatchBootWimApply_script_contains_apply_lane_steps_not_legacy_setup` and `Patcher_and_gate_certify_every_boot_wim_index` entirely. Keep `Apply_materializes_winpe_opcode_params` (ImageServicing seam). Keep `BuildIso_script_does_not_finalize_plan_evidence` (C# owns `evidence.json` — kernels must not write it).

If `FindPatchBootScript` / `FindRepoFile` become unused in this class, delete those helpers too.

- [ ] **Step 2: Run WinPeApplyPlanTests**

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~WinPeApplyPlanTests"
pwsh -NoProfile -File tests/contract/Test-DiskGuard.ps1
```

Expected: both PASS. DiskGuard still executes LaunchApply / helper-hash / wrong-index defects.

- [ ] **Step 3: Commit**

```bash
git add tests/WinMint.Tests/WinPeApplyPlanTests.cs
git commit -m "test(winpe): drop Patch-Boot source greps that DiskGuard already runs"
```

---

### Task 4: Delete `Test-PolicyPayloadJson.ps1` (Worth exploring / C4)

**Files:**
- Delete: `tests/contract/Test-PolicyPayloadJson.ps1`
- Unchanged: `tests/WinMint.Tests/ImageServicingApplyTests.cs` fact `Apply_policy_payload_json_round_trips_semicolon_pipe_and_tilde_in_data`

**Interfaces:**
- Consumes: `ImageServicing.ApplyAsync` writing `payload/policies.json` and `StampOfflinePolicies` `StageParams.PoliciesPath` (already asserted).
- Produces: `just contract-tests` no longer discovers `Test-PolicyPayloadJson.ps1`.

- [ ] **Step 1: Confirm the C# fact owns the punctuation round-trip**

Open `Apply_policy_payload_json_round_trips_semicolon_pipe_and_tilde_in_data`. It already uses data `semi;pipe|tilde~~~~end` and asserts `payload/policies.json` plus `policySpecs` absent. That is the interface. The contract script greps `ConvertFrom-Json` then round-trips a tempfile without calling `Stamp-OfflinePolicies.ps1`.

- [ ] **Step 2: Delete the contract script**

Delete `tests/contract/Test-PolicyPayloadJson.ps1`. Discovery is `Get-ChildItem tests/contract -Filter Test-*.ps1` — no Justfile edit.

- [ ] **Step 3: Run contract discovery + the C# fact**

```powershell
pwsh -NoProfile -File tests/contract/Invoke-ContractTests.ps1
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~Apply_policy_payload_json_round_trips"
```

Expected: contract runner lists every remaining `Test-*.ps1` and does **not** list `Test-PolicyPayloadJson.ps1`; all remaining contract tests PASS; C# fact PASS.

- [ ] **Step 4: Commit**

```bash
git add tests/contract/Test-PolicyPayloadJson.ps1
git commit -m "test(servicing): drop PolicyPayloadJson grep; Apply owns the round-trip"
```

---

### Task 5: Prepared-media audit on `ImageEvidence`, not `evidence.json` (Speculative / C5)

**Files:**
- Modify: `src/WinMint.Orchestrator/ImageServicing.Types.cs`
- Modify: `src/WinMint.Orchestrator/ImageServicing.Evidence.cs`
- Modify: `tests/WinMint.Tests/ImageServicingApplyTests.cs` (`Apply_keeps_prepared_media_fields_off_typed_evidence`)
- Unchanged: `tests/WinMint.Tests/ApplyEvidenceAssertTests.cs`, `SmokeEvidenceAssertTests.cs` (S5/S4 may still open evidence files)

**Interfaces:**
- Consumes: `WriteEvidence` already copies selected audit keys onto the JSON document and omits `mediaCache.previousMedia`.
- Produces: `ImageEvidence` gains `IReadOnlyDictionary<string, string> PreparedMediaFields` (empty dictionary when no audit file). String audit keys that `CopyPreparedMediaAudit` already copies (`mediaCache.outcome`, `source.isoSha256`, …) appear there. `Digests` still must not contain `mediaCache.outcome` / `source.isoSha256`. `mediaCache.previousMedia` must not appear in `PreparedMediaFields`. File write of `evidence.json` stays implementation.

- [ ] **Step 1: Write the failing Apply test**

In `Apply_keeps_prepared_media_fields_off_typed_evidence`, delete the `JsonDocument.Parse(File.ReadAllBytes(... evidence.json))` block. Assert through `result.Value`:

```csharp
Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
Assert.Equal(ImageQualityLane.Test, result.Value.Lane);
Assert.False(result.Value.Digests.ContainsKey("source.isoSha256"));
Assert.False(result.Value.Digests.ContainsKey("mediaCache.outcome"));
Assert.Equal("hit", result.Value.PreparedMediaFields["mediaCache.outcome"]);
Assert.False(result.Value.PreparedMediaFields.ContainsKey("mediaCache.previousMedia"));
Assert.Equal(new string('a', 64), result.Value.Digests["outputIso.sha256"]);
```

- [ ] **Step 2: Run to verify it fails**

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~Apply_keeps_prepared_media_fields_off_typed_evidence"
```

Expected: FAIL — `PreparedMediaFields` does not exist.

- [ ] **Step 3: Add the field and fill it in `WriteEvidence`**

`ImageEvidence` record:

```csharp
public sealed record ImageEvidence(
    string OutputIsoPath,
    ImageQualityLane Lane,
    string ShellStampTargetPath,
    IReadOnlyDictionary<string, string> Digests,
    IReadOnlyDictionary<string, string> PreparedMediaFields);
```

`WriteEvidence` return:

```csharp
Dictionary<string, string> preparedFields = [];
if (File.Exists(workspace.PreparedMedia))
{
    // existing deserialize + schema fail-closed
    CopyPreparedMediaAudit(doc, audit, preparedFields);
}

File.WriteAllText(workspace.Evidence, doc.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));

return Result.Ok<ImageEvidence, Failure>(
    new ImageEvidence(
        run.OutputIsoPath,
        plan.Manifest.ImageQuality,
        shellTarget,
        digests.ToFrozenDictionary(StringComparer.Ordinal),
        preparedFields.ToFrozenDictionary(StringComparer.Ordinal)));
```

When there is no `prepared-media.json`, pass `FrozenDictionary<string, string>.Empty`.

Change `CopyPreparedMediaAudit` to also `preparedFields[key] = value` for every `SetIfPresent` string key. Do not copy `MediaCachePreviousMedia`. Numeric timings may stay JSON-only (this test does not need them).

Only one `new ImageEvidence(` exists today — update that site. No other call sites.

- [ ] **Step 4: Run the fact + full S2 Apply tests**

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~ImageServicingApplyTests"
```

Expected: PASS. `ApplyEvidenceAssertTests` still compile (they do not construct `ImageEvidence`).

- [ ] **Step 5: Commit**

```bash
git add src/WinMint.Orchestrator/ImageServicing.Types.cs src/WinMint.Orchestrator/ImageServicing.Evidence.cs tests/WinMint.Tests/ImageServicingApplyTests.cs
git commit -m "test(servicing): observe prepared-media audit on ImageEvidence"
```

---

### Task 6: Lock disk-boot: no Hyper-V adapter for four-line decisions (Speculative / C6)

**Files:**
- Modify: `docs/TDD.md` (Don’t table + S4 + contract greps sentence)
- Unchanged: `Get-SmokePreferDiskBootDecision`, `Get-SmokeEjectDvdDecision`, `Get-SmokeVmStartupBytes`, `tests/contract/Test-SmokeDiskBoot.ps1` wait-loop grep and `Prefer-DiskBoot` / `Set-VMDvdDrive` slice

**Interfaces:**
- Consumes: existing disk-boot policy functions (in-process) and firmware sequencing greps (host cannot run here).
- Produces: TDD forbids injecting `Get-VHD` / `Set-VMFirmware` / `Set-VMDvdDrive` adapters so tests can call `Prefer-DiskBoot`. Do **not** delete the four-line decision functions (Task 1’s neighbor tests already drive them). Do **not** add a fake VM.

- [ ] **Step 1: Write the Don’t into TDD.md**

Speed-rules **Don’t** row — keep the existing two clauses and add the third:

`Skip S4 hard evidence; invent a Hyper-V-only settle/executor path “for speed”; inject Hyper-V cmdlet adapters to unit-test Prefer-DiskBoot`

Contract paragraph — keep wait-loop firmware sequencing greps. Add: four-line `Get-SmokePreferDiskBootDecision` / `Get-SmokeEjectDvdDecision` stay; they are not a second adapter. A fake `Set-VMFirmware` is a hypothetical seam (one adapter) and is forbidden.

S4 paragraph — already says disk-boot tests drive those policy functions, not a Hyper-V executor. Add: do not “complete” that by faking Hyper-V.

- [ ] **Step 2: Prove the existing disk-boot contract still holds**

```powershell
pwsh -NoProfile -File tests/contract/Test-SmokeDiskBoot.ps1
```

Expected: `Test-SmokeDiskBoot ok`. `Prefer-DiskBoot` body still must not contain `Set-VMDvdDrive`. `Running { Prefer-DiskBoot` grep still present.

- [ ] **Step 3: Commit**

```bash
git add docs/TDD.md
git commit -m "docs: forbid Hyper-V adapters for Smoke disk-boot tests"
```

---

### Task 7: Gate — `just check`

**Files:** none new

**Interfaces:** none — whole-tree verification.

- [ ] **Step 1: Run `just check`**

```powershell
just check
```

Expected: exit 0. `dotnet format --verify-no-changes` clean. xUnit 0 failures (S4/S5 filtered). PSScriptAnalyzer clean. Contract runner does not print `Test-PolicyPayloadJson.ps1`. `Test-SmokeStatus ok`, `Test-SmokeDiskBoot ok`, `Test-DiskGuard` still listed.

- [ ] **Step 2: No extra commit** unless `just check` forced a format fix — then commit that fix as `style: format after test-suite deepening` and re-run Step 1.

---

## Self-review

**Spec coverage (review cards → tasks):**

| Card | Strength | Task |
| --- | --- | --- |
| Waiter and tests share one Smoke wait-policy module | Strong | 1 |
| Freshness and pwsh path through the runner interface | Worth exploring | 2 (`CheckPublishedBinaryFreshness`, `RefuseStoreMsixPwsh`; not `ExecuteAsync`) |
| Stop grepping Patch-BootWimApply from C# | Worth exploring | 3 |
| Policy JSON tests ImageServicing | Worth exploring | 4 |
| Apply tests observe ImageEvidence | Speculative | 5 |
| Do not fake Hyper-V for disk-boot | Speculative | 6 |
| Gate | — | 7 |

**Not in scope (review said don’t):** second ImageServicing port; Hyper-V in `just check`; re-doing `WinPeApplyHost.Run` / `Get-WinPeApplyDefect` SHA256; deleting wait-loop firmware greps; treating S4/S5 evidence asserts as mailbox bugs; `FlashGuidance.Format` tests; `Test-ReleaseSigningPolicy` markdown greps.

**C2 narrowing:** `ExecuteAsync` is not called from tests (UAC). `RefuseStoreMsixPwsh` + `CheckPublishedBinaryFreshness` are the in-process seam. ADR-009 still lives on the runner.

**Placeholder scan:** no TBD/TODO; `CheckPublishedBinaryFreshness` uses one interpolated failure message.
