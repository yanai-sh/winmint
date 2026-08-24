# FirstLogon chrome + hypervisor WSL mock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harvest v1 FirstLogon desktop (bloom, Start/taskbar replace, quiet chrome, default AppX strip including third-party/OEM + WhatsApp) and mock WSL on hypervisor guests so Hyper-V Smoke can Complete.

**Architecture:** ImageServicing stages bloom into the offline image. `ProductPosture.AppxIds` becomes the v1 default strip (all five groups + WhatsApp, minus preserve/exempt). Supervisor adds hypervisor-guest WSL mock, a real safety-net verify, `workstation.quiet` DWords, and a new `shell.chrome` job after packages. Fail-open paints baseline chrome. Smoke asserts phases + `guest/shell-chrome.json`.

**Tech Stack:** net11.0 C# (Orchestrator + Provisioning AOT), xUnit v3, pwsh 7.6 servicing (`Stage-Payload.ps1`), `Assert-SmokeEvidence.ps1`.

**Spec:** [docs/superpowers/specs/2026-08-24-firstlogon-chrome-wsl-mock-design.md](../specs/2026-08-24-firstlogon-chrome-wsl-mock-design.md)

## Global Constraints

- CLI/Orchestrator creates intent; Servicing mutates the offline image; Supervisor finishes FirstLogon.
- No v1 guest pwsh forest. No Profile `diagnostics.*`. No `HypervisorPresent` (SL7 metal is a Hyper-V host).
- `just check` stays green; no Hyper-V inside `just check`.
- Product constants live in `ProductPosture` / catalog — no preset names in Profile JSON (ADR-005 / ADR-009).
- v1 `preserve` + `systemExemptPrefixes` are never removed. sl7 keeps Phone Link (drop `YourPhone` / `WindowsAlarms` from authored sl7).
- Wallpaper dest: `C:\Windows\Web\Wallpaper\Windows\WinMint-Bloom.jpg`.
- WSL mock: any hypervisor *guest*; metal installs. Nested virt exposed still mocks.
- Green Smoke requires `Complete` / `jobs.ok` / `oobe.dismiss` / `jobs.wsl.platform.mocked` / `shell.chrome` / `shell-chrome.json`. Fail-open chrome is not green.
- This existing Failed VM is out of scope (new Apply/Smoke after implement).

## File map

| File | Responsibility |
|------|----------------|
| `src/WinMint.Orchestrator/ProductPosture.cs` | Expand `AppxIds`; add `PreserveAppx`; `UnionAppx` drops preserve |
| `src/WinMint.Orchestrator/ProvisionedAppxCatalog.cs` | Legal ids for the expanded strip |
| `src/WinMint.Orchestrator/BuildPlan.cs` / `BuildPlan.Packages.cs` | Always emit `shell.chrome` after package/WSL jobs |
| `src/WinMint.Orchestrator/ImageServicing.Materialize.cs` | Copy bloom into work `payloadDir` or fail Apply |
| `servicing/Stage-Payload.ps1` | Copy bloom onto the mounted image |
| `payload/media/wallpaper/bloom.jpg` | JPEG bytes from v1 `assets/runtime/wallpaper/img0.jpg` |
| `samples/sl7.profile.json` | Drop `WindowsAlarms` and `YourPhone` |
| `src/WinMint.Contracts/ProvisionJobKind.cs` | `ShellChrome` / `shell.chrome` |
| `src/WinMint.Provisioning/HypervisorGuest.cs` | Pure guest detect |
| `src/WinMint.Provisioning/Win32HypervisorGuest.cs` | CIM + Hyper-V Guest key |
| `src/WinMint.Provisioning/Win32WslTerminalMock.cs` | Best-effort Fedora mock profile |
| `src/WinMint.Provisioning/ShellChromeLayout.cs` | Start JSON + taskbar XML (pure) |
| `src/WinMint.Provisioning/Win32ShellChrome.cs` | SPI / registry / evidence write |
| `src/WinMint.Provisioning/Win32WorkstationQuiet.cs` | Remaining v1 quiet DWords |
| `src/WinMint.Provisioning/ProvisioningSession*.cs` | Job + fail-open + `IGuestMachine` ports |
| `tools/vm/Assert-SmokeEvidence.ps1` | New phase + `shell-chrome.json` gates |
| `tests/fixtures/smoke-evidence/` | Fixture updates |

---

### Task 1: Default AppX strip (v1 groups + WhatsApp, preserve Clock)

**Files:**
- Modify: `src/WinMint.Orchestrator/ProductPosture.cs` (`AppxIds`, add `PreserveAppx` / `PreserveAppxSet`, change `UnionAppx`)
- Modify: `src/WinMint.Orchestrator/ProvisionedAppxCatalog.cs`
- Modify: `src/WinMint.Provisioning/AppxCatalogFamilyNames.cs` (PFNs for new ids that are not `*_8wekyb3d8bbwe`)
- Modify: `samples/sl7.profile.json` (remove `Microsoft.WindowsAlarms`, `Microsoft.YourPhone`)
- Modify: `tests/WinMint.Tests/ProductPostureTests.cs`
- Modify: any test that asserts exact `AppxIds` length (update to the new set)

**Interfaces:**
- Consumes: v1 `config/appx-removal.json` groups `coreMicrosoft`, `communication`, `gaming`, `consumerThirdParty`, `oemConsumer` plus `5319275A.WhatsAppDesktop`
- Produces: `ProductPosture.AppxIds` (IReadOnlyList<string>), `ProductPosture.PreserveAppxSet` (IReadOnlySet<string>), `UnionAppx(profile)` = `(profile ∪ AppxIds)` minus `PreserveAppxSet`

- [ ] **Step 1: Write the failing test**

In `tests/WinMint.Tests/ProductPostureTests.cs` add:

```csharp
[Fact]
public void UnionAppx_includes_v1_default_groups_and_whatsapp_and_drops_clock()
{
    IReadOnlyList<string> merged = ProductPosture.UnionAppx(["Microsoft.WindowsAlarms", "Microsoft.BingNews"]);

    Assert.DoesNotContain("Microsoft.WindowsAlarms", merged);
    Assert.Contains("Microsoft.BingNews", merged);
    Assert.Contains("Clipchamp.Clipchamp", merged);
    Assert.Contains("Microsoft.OutlookForWindows", merged);
    Assert.Contains("MicrosoftWindows.Client.WebExperience", merged);
    Assert.Contains("Microsoft.WindowsCalculator", merged);
    Assert.Contains("MSTeams", merged);
    Assert.Contains("5319275A.WhatsAppDesktop", merged);
    Assert.Contains("LinkedInforWindows", merged);
    Assert.Contains("SpotifyAB.SpotifyMusic", merged);
    Assert.Contains("4DF9E0F8.Netflix", merged);
    Assert.Contains("AD2F1837.HPWelcome", merged);
    Assert.DoesNotContain("Microsoft.WindowsStore", merged);
    Assert.DoesNotContain("Microsoft.WindowsCamera", merged);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter FullyQualifiedName~UnionAppx_includes_v1_default_groups`

Expected: FAIL — `Clipchamp.Clipchamp` / WhatsApp missing.

- [ ] **Step 3: Write minimal implementation**

Copy every prefix from v1 `..\winmint_v1\config\appx-removal.json` groups `coreMicrosoft`, `communication`, `gaming`, `consumerThirdParty`, `oemConsumer` into `ProductPosture.AppxIds`, then append `"5319275A.WhatsAppDesktop"`.

`PreserveAppx` = v1 `preserve` + v1 `systemExemptPrefixes` (Store, Camera, `WindowsAlarms`, Notepad, Photos, Paint, Edge/WebView2, OEM *support* tools, `XboxGameCallableUI`, `MicrosoftWindows.Client.CBS`, …).

```csharp
public static IReadOnlyList<string> UnionAppx(IReadOnlyList<string> profileAppx) =>
    [.. IdList.UnionOrdered(profileAppx, AppxIds)
        .Where(id => !PreserveAppxSet.Contains(id))];
```

Add every new id to `ProvisionedAppxCatalog.Ids` so plan validation accepts them.

In `AppxCatalogFamilyNames`, add non-Store PFNs you already special-case (Clipchamp). WhatsApp: `5319275A.WhatsAppDesktop_cv1g1gvanyjgm` if that is the live family; otherwise `Resolve` default (`{id}_8wekyb3d8bbwe`) is fine until safety-net prefix match (Task 5).

Delete `Microsoft.WindowsAlarms` and `Microsoft.YourPhone` from `samples/sl7.profile.json`.

- [ ] **Step 4: Run tests**

Run: `just check`

Expected: PASS. Fix any DebloatPreset/Wizard tests that assumed the old 5-id posture list.

- [ ] **Step 5: Commit**

```bash
git add src/WinMint.Orchestrator/ProductPosture.cs src/WinMint.Orchestrator/ProvisionedAppxCatalog.cs src/WinMint.Provisioning/AppxCatalogFamilyNames.cs samples/sl7.profile.json tests/WinMint.Tests/ProductPostureTests.cs
git commit -m "feat(orchestrator): default AppX strip matches v1 groups plus WhatsApp"
```

---

### Task 2: Stage WinMint bloom into the image

**Files:**
- Create: `payload/media/wallpaper/bloom.jpg` (copy bytes from `C:\Users\yanai\Projects\winmint_v1\assets\runtime\wallpaper\img0.jpg`; if that path is missing, copy `winmint-bloom.png` converted to JPEG — the dest name must be `.jpg`)
- Modify: `src/WinMint.Orchestrator/ImageServicing.Materialize.cs` (stage bloom into work `payloadDir` next to Supervisor, fail `servicing.bloom.missing` if source missing)
- Modify: `servicing/Stage-Payload.ps1`
- Test: `tests/contract/Test-StagePayloadBloom.ps1` (new, invoked from existing contract runner if one dotsources `tests/contract/*.ps1`) or `tests/WinMint.Tests` if contracts are enumerated in `just check`

**Interfaces:**
- Consumes: repo `payload/media/wallpaper/bloom.jpg`
- Produces: mounted `Windows\Web\Wallpaper\Windows\WinMint-Bloom.jpg`

- [ ] **Step 1: Write the failing contract**

`tests/contract/Test-StagePayloadBloom.ps1`:

```powershell
#requires -Version 7.6
Set-StrictMode -Version Latest
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$bloom = Join-Path $repo 'payload\media\wallpaper\bloom.jpg'
if (-not (Test-Path -LiteralPath $bloom -PathType Leaf)) { throw "bloom.jpg missing: $bloom" }
if ((Get-Item -LiteralPath $bloom).Length -lt 1KB) { throw 'bloom.jpg too small' }
$stage = Get-Content -LiteralPath (Join-Path $repo 'servicing\Stage-Payload.ps1') -Raw
if ($stage -notmatch 'WinMint-Bloom\.jpg') { throw 'Stage-Payload.ps1 must copy WinMint-Bloom.jpg' }
```

- [ ] **Step 2: Run to verify it fails**

Run: `pwsh -File tests/contract/Test-StagePayloadBloom.ps1`

Expected: FAIL — file or copy line missing.

- [ ] **Step 3: Implement**

Copy v1 `img0.jpg` → `payload/media/wallpaper/bloom.jpg`.

In `ImageServicing.Materialize` (same place as `StageShellSkel`):

```csharp
private static Result<string, Failure> StageBloomWallpaper(string payloadDir)
{
    string? source = ToolkitRoot.TryFind("payload", "media", "wallpaper", "bloom.jpg");
    if (source is null)
        return Result.Fail<string, Failure>(new Failure("servicing.bloom.missing", "payload/media/wallpaper/bloom.jpg not found."));
    string dest = Path.Combine(payloadDir, "bloom.jpg");
    File.Copy(source, dest, overwrite: true);
    return Result.Ok<string, Failure>(dest);
}
```

Call it from the existing payload staging sequence; fail Apply if not Ok.

`servicing/Stage-Payload.ps1` after the existing copies:

```powershell
$bloomSrc = Join-Path $payloadDir 'bloom.jpg'
if (-not (Test-Path -LiteralPath $bloomSrc -PathType Leaf)) {
    Write-Error 'StagePayload: bloom.jpg missing from payloadDir'
    exit 1
}
$wallpaperDir = Join-Path $mountDir 'Windows\Web\Wallpaper\Windows'
New-Item -ItemType Directory -Force -Path $wallpaperDir | Out-Null
Copy-Item -LiteralPath $bloomSrc -Destination (Join-Path $wallpaperDir 'WinMint-Bloom.jpg') -Force
```

- [ ] **Step 4: Run contract + `just check`**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add payload/media/wallpaper/bloom.jpg servicing/Stage-Payload.ps1 src/WinMint.Orchestrator/ImageServicing.Materialize.cs tests/contract/Test-StagePayloadBloom.ps1
git commit -m "feat(servicing): stage WinMint bloom wallpaper into install image"
```

---

### Task 3: Quiet taskbar DWords (v1 `Set-WinMintFirstLogonQuietUxDefaults`)

**Files:**
- Modify: `src/WinMint.Provisioning/Win32WorkstationQuiet.cs`
- Test: `tests/WinMint.Tests/WorkstationQuietLayoutTests.cs` (new) — test a **public** key/value table, not live HKCU

**Interfaces:**
- Consumes: existing `Win32WorkstationQuiet.Apply()`
- Produces: `Win32WorkstationQuiet.UserDwords` rows the Apply loop writes

- [ ] **Step 1: Write the failing test**

```csharp
[Fact]
public void Quiet_table_includes_v1_taskbar_and_search_dwords()
{
    IReadOnlyDictionary<string, int> advanced = Win32WorkstationQuiet.ExplorerAdvancedDwords;
    Assert.Equal(0, advanced["ShowTaskViewButton"]);
    Assert.Equal(0, advanced["TaskbarDa"]);
    Assert.Equal(0, advanced["TaskbarMn"]);
    Assert.Equal(0, advanced["ShowCopilotButton"]);
    Assert.Equal(0, Win32WorkstationQuiet.SearchboxTaskbarMode);
    Assert.Equal(1, Win32WorkstationQuiet.HideRecycleBin);
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter FullyQualifiedName~Quiet_table_includes_v1`

Expected: FAIL — members missing.

- [ ] **Step 3: Implement**

Expose the table. In `ApplyUserRegistry`, write:

- `HKCU\Software\Microsoft\Windows\CurrentVersion\Search` `SearchboxTaskbarMode` = 0
- Explorer\Advanced: `ShowTaskViewButton`, `TaskbarDa`, `TaskbarMn`, `ShowCopilotButton`, `Start_AccountNotifications` = 0 (keep existing `TaskbarDa` / `TaskbarEndTask`)
- Hide Recycle Bin: `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel` and `ClassicStartMenu` `{645FF040-5081-101B-9F08-00AA002F954E}` = 1
- CDM spray off (v1 names): `SubscribedContent-338388Enabled` and the other v1 `ContentDeliveryManager` DWords = 0

Do not throw (existing best-effort).

- [ ] **Step 4: `just check`**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/WinMint.Provisioning/Win32WorkstationQuiet.cs tests/WinMint.Tests/WorkstationQuietLayoutTests.cs
git commit -m "feat(provisioning): harvest v1 quiet taskbar and CDM DWords"
```

---

### Task 4: Hypervisor guest detect + WSL mock

**Files:**
- Create: `src/WinMint.Provisioning/HypervisorGuest.cs`
- Create: `src/WinMint.Provisioning/Win32HypervisorGuest.cs`
- Create: `src/WinMint.Provisioning/Win32WslTerminalMock.cs` (best-effort; swallow errors)
- Modify: `src/WinMint.Provisioning/ProvisioningSession.Types.cs` (`IGuestMachine.IsHypervisorGuest()`)
- Modify: `src/WinMint.Provisioning/Win32GuestMachine.cs`
- Modify: `src/WinMint.Provisioning/ProvisioningSession.JobRunner.cs` (`JobRunnerEnv` + `WslMocked` flag)
- Modify: `src/WinMint.Provisioning/ProvisioningSession.JobRunner.Wsl.cs`
- Modify: `src/WinMint.Provisioning/ProvisioningSession.cs` (pass `IsHypervisorGuest`)
- Modify: `tests/WinMint.Tests/ProvisioningSessionTestFakes.cs`
- Modify: `tests/WinMint.Tests/WslJobsTests.cs`

**Interfaces:**
- Consumes: manufacturer, model, `hyperVGuestKeyExists`
- Produces:

```csharp
public static class HypervisorGuest
{
    public static bool IsGuest(string? manufacturer, string? model, bool hyperVGuestKeyExists);
}
```

`IGuestMachine.IsHypervisorGuest()` → Win32 reads `Win32_ComputerSystem` + `HKLM\SOFTWARE\Microsoft\Virtual Machine\Guest`. Probe throw → `false`.

`JobRunnerEnv` gains `Func<bool> IsHypervisorGuest` and a mutable `bool WslMocked` (use a small `WslMockState { public bool Mocked; }` so the record can share it).

- [ ] **Step 1: Write failing tests**

`tests/WinMint.Tests/HypervisorGuestTests.cs`:

```csharp
[Fact]
public void HyperV_virtual_machine_is_guest()
{
    Assert.True(HypervisorGuest.IsGuest("Microsoft Corporation", "Virtual Machine", hyperVGuestKeyExists: false));
}

[Fact]
public void Sl7_host_desktop_is_not_guest_even_if_caller_might_see_hypervisor()
{
    Assert.False(HypervisorGuest.IsGuest("Microsoft Corporation", "Surface Laptop 7", hyperVGuestKeyExists: false));
}

[Fact]
public void HyperV_guest_key_alone_is_guest()
{
    Assert.True(HypervisorGuest.IsGuest("Unknown", "Unknown", hyperVGuestKeyExists: true));
}
```

`WslJobsTests`:

```csharp
[Fact]
public async Task Shell_wsl_platform_mocks_on_hypervisor_guest_and_skips_distro()
{
    RecordingProcessHost processes = new();
    RecordingEvidenceSink evidence = new();
    SessionResult result = await ProvisioningSession.RunShellAsync(
        Bundle(jobs:
        [
            new ProvisionJob("wsl.platform", ProvisionJobKind.WslPlatform),
            new ProvisionJob("wsl.FedoraLinux", ProvisionJobKind.Wsl, PackageId: "FedoraLinux"),
        ]),
        Env(processes, evidence, isWslPlatformReady: static () => false, isHypervisorGuest: static () => true),
        TestContext.Current.CancellationToken);

    Assert.Equal(SessionOutcome.Complete, result.Outcome);
    Assert.DoesNotContain(processes.Starts, s => s.FileName.Equals("wsl.exe", StringComparison.OrdinalIgnoreCase));
    Assert.Contains("jobs.wsl.platform.mocked", evidence.Documents[^1].Phases);
    Assert.Contains("jobs.wsl.FedoraLinux.mocked", evidence.Documents[^1].Phases);
}
```

Keep `Shell_wsl_platform_missing_installs_and_reboots_on_3010` with `isHypervisorGuest: () => false`.

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement**

`HypervisorGuest.IsGuest`: true if `hyperVGuestKeyExists`; or manufacturer contains `Microsoft` and model contains `Virtual Machine`; or manufacturer/model contains VMware, VirtualBox, QEMU, KVM, Xen (ordinal ignore case).

`RunWslPlatformJobAsync`: if `env.IsHypervisorGuest()` → set `WslMocked`, `ReportStatus(jobs.wsl.platform.mocked)`, call `Win32WslTerminalMock.TryStage(distro names from remaining Wsl jobs)` inside try/catch, return null (do not run `wsl.exe`).

Each later `Wsl` / from-file job: if `WslMocked` → `jobs.{id}.mocked` and continue.

Wire `Env(..., isHypervisorGuest: )` in test fakes. Default `false`.

- [ ] **Step 4: `just check`**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(provisioning): mock WSL on hypervisor guests"
```

---

### Task 5: Safety net must remove leftovers, not only stamp marks

**Files:**
- Modify: `src/WinMint.Provisioning/ProvisioningSession.JobRunner.Packages.cs` (`RunAppxSafetyNetJobAsync`)
- Modify: `src/WinMint.Provisioning/WinRTAppxPackageManager.cs` (`FindRegisteredByCatalogId` / `FindProvisionedByCatalogId` — prefix match on Name/PFN)
- Modify: `tests/WinMint.Tests/DebloatAppxSafetyNetTests.cs`

**Interfaces:**
- Consumes: existing `IAppxPackageManager`
- Produces: after the loop, if any catalog id still has a registered or provisioned hit → `FailJob(..., "jobs.failed", "...")`. Vacuous `removed.appx.online.*` still forbidden when no hit.

- [ ] **Step 1: Write the failing test**

```csharp
[Fact]
public async Task Shell_appx_safetyNet_fails_when_family_still_visible_after_remove()
{
    RecordingAppx appx = new() { RemoveIsNoOp = true };
    appx.Registered.Add(new AppxPackageInfo(
        "Microsoft.MicrosoftSolitaireCollection_1.0.0.0_neutral__8wekyb3d8bbwe",
        "Microsoft.MicrosoftSolitaireCollection_8wekyb3d8bbwe",
        "Microsoft.MicrosoftSolitaireCollection"));

    SessionResult result = await ProvisioningSession.RunShellAsync(
        Bundle(
            jobs: [new ProvisionJob("debloat.appx.safetyNet", ProvisionJobKind.AppxSafetyNet)],
            removeProvisionedAppx: ["Microsoft.MicrosoftSolitaireCollection"]),
        Env(new FakeGuestMachine { Appx = appx }, new RecordingEvidenceSink()),
        TestContext.Current.CancellationToken);

    Assert.Equal(SessionOutcome.Failed, result.Outcome);
}
```

Add `RemoveIsNoOp` to `RecordingAppx` so `RemovePackageAsync` does not drop the list.

- [ ] **Step 2: Run — expect FAIL** (today Complete + marks only)

- [ ] **Step 3: Implement**

After existing remove/deprovision/marks, re-query. If any `removeProvisionedAppx` id still matches registered or provisioned → `return FailJob(env, "jobs.failed", $"Job '{job.Id}': '{id}' still present after safety net.");`

Prefix match: catalog id `LinkedInforWindows` matches `7EE7776C.LinkedInforWindows`.

Keep the existing vacuous-absent test green.

- [ ] **Step 4: `just check`**

- [ ] **Step 5: Commit**

```bash
git commit -m "fix(provisioning): AppX safety net fail-closes if family still present"
```

---

### Task 6: `shell.chrome` job — layout + apply + evidence

**Files:**
- Modify: `src/WinMint.Contracts/ProvisionJobKind.cs` (`ShellChrome`, wire `shell.chrome`, TryParse/ToWire)
- Modify: `src/WinMint.Orchestrator/BuildPlan.cs` — after `jobList.AddRange(packageSlice.Jobs);` add `new ProvisionJob("shell.chrome", ProvisionJobKind.ShellChrome)`
- Create: `src/WinMint.Provisioning/ShellChromeLayout.cs`
- Create: `src/WinMint.Provisioning/Win32ShellChrome.cs`
- Create: `src/WinMint.Provisioning/ShellChromeEvidenceFile.cs` (`winmint.shell.chrome/v1`)
- Modify: `ProvisioningSession.Types.cs` — `IGuestMachine.ApplyShellChrome(ShellChromeRequest request)`
- Modify: `JobRunner` switch + `JobRunner.Packages.cs` `RunShellChromeJob`
- Modify: `BundleLoaderTests` / plan tests that list every `ProvisionJobKind`
- Test: `tests/WinMint.Tests/ShellChromeLayoutTests.cs`, `tests/WinMint.Tests/ShellChromeJobTests.cs`
- STJ: register `ShellChromeEvidenceFile` on the existing provisioning JSON context

**Interfaces:**

```csharp
public sealed record ShellChromeRequest(
    bool FailOpen,
    IReadOnlyList<string> SelectedWingetIds);

public sealed record ShellChromeEvidenceFile(
    string SchemaVersion,
    string WallpaperPath,
    string[] StartPinIds,
    string[] TaskbarPinIds,
    IReadOnlyDictionary<string, int> QuietDwords);

public static class ShellChromeLayout
{
    public const string WallpaperPath = @"C:\Windows\Web\Wallpaper\Windows\WinMint-Bloom.jpg";
    public static string ConfigureStartPinsJson(IReadOnlyList<string> desktopLinkPaths);
    public static string TaskbarLayoutXml(IReadOnlyList<string> desktopLinkPaths);
    public static string? TryResolveShortcut(string wingetId); // Cursor / Zen paths like v1
}
```

Start JSON `pinnedList`: Explorer `desktopAppId=Microsoft.Windows.Explorer`, Settings `packagedAppId=windows.immutablecontrolpanel`, Terminal `packagedAppId=Microsoft.WindowsTerminal_8wekyb3d8bbwe!App`, then each resolved `.lnk`.

Taskbar XML: `PinListPlacement="Replace"`, Explorer + Terminal UWA, then DesktopApp link paths. No Edge when Zen is in `SelectedWingetIds`.

Evidence path: `%ProgramData%\WinMint\shell-chrome.json` (same folder Smoke already pulls).

- [ ] **Step 1: Failing tests**

`ShellChromeLayoutTests`: assert JSON contains `Microsoft.Windows.Explorer`, `windows.immutablecontrolpanel`, Terminal AUMID; XML contains `PinListPlacement="Replace"` and does not contain `Microsoft.Xbox`.

`BuildPlan` test: sl7-like profile with Fedora + Cursor → jobs contain `shell.chrome` **after** `wsl.*`.

`ShellChromeJobTests`: fake `ApplyShellChrome` records the request; Complete evidence contains `shell.chrome`; missing wallpaper on Complete → Failed (fake throws / returns false when `FailOpen` is false and wallpaper missing).

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

Wire kind. Emit job last (after native audit too — `AddRange(packageSlice.Jobs)` already ends with WSL/audit; append chrome after that).

`RunShellChromeJob`: collect winget ids from the **full** job list (`Winget` `PackageId` plus `Anysphere.Cursor` / `Zen-Team.Zen-Browser` if present in import — if import-only, read `BundleLoader.DefaultGuestWingetImportPath` when it exists). Call `env.ApplyShellChrome(new(FailOpen: false, ids))`. On false → `FailJob`. On success → `ReportStatus(shell.chrome)`.

`Win32ShellChrome.Apply`: if bloom file missing and not fail-open → return false. Else SPI 20 + HKCU Desktop Wallpaper/WallpaperStyle=10. Write ConfigureStartPins to HKCU and HKLM Policies\Microsoft\Windows\Explorer. Write `%LOCALAPPDATA%\Microsoft\Windows\Shell\LayoutModification.xml`. Resolve Cursor/Zen shortcuts (v1 candidate paths). If a selected id has no exe/lnk and not fail-open → return false. Write evidence JSON.

`Win32GuestMachine.ApplyShellChrome` delegates. Fake records.

- [ ] **Step 4: `just check`**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(provisioning): apply WinMint Start/taskbar chrome and bloom"
```

---

### Task 7: Fail-open baseline chrome

**Files:**
- Modify: `src/WinMint.Provisioning/ProvisioningSession.cs` `FailOpenAsync` — after Failed evidence, before `TryUnlock`, call `ApplyShellChrome(new(FailOpen: true, SelectedWingetIds: []))` inside try/catch (do not change Failed outcome)
- Test: `tests/WinMint.Tests/ShellChromeJobTests.cs` (or Unlock/FailOpen existing test)

**Interfaces:**
- Consumes: `IGuestMachine.ApplyShellChrome`
- Produces: fail-open still `SessionOutcome.Failed`; fake shows `FailOpen: true`

- [ ] **Step 1: Failing test** — run jobs that fail (existing WSL install fail with guest=false), assert `ApplyShellChrome` was invoked with `FailOpen: true` and outcome is still Failed.

- [ ] **Step 2: Run — expect FAIL** (no call today)

- [ ] **Step 3: Implement** the one call in `FailOpenAsync`. Do not add `shell.chrome` to Failed phases (same as `oobe.dismiss`).

- [ ] **Step 4: `just check`**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(provisioning): apply baseline chrome on fail-open unlock"
```

---

### Task 8: Smoke assert + fixture

**Files:**
- Modify: `tools/vm/Assert-SmokeEvidence.ps1`
- Modify: `tests/fixtures/smoke-evidence/guest/evidence-*.json` (add phases `jobs.workstation.quiet`, `jobs.wsl.platform.mocked`, `shell.chrome`)
- Create: `tests/fixtures/smoke-evidence/guest/shell-chrome.json`
- Modify: `tests/WinMint.Tests/SmokeEvidenceAssertTests.cs` if fixture parse assumes old phase set
- Modify: `tests/contract/Test-SmokeStatus.ps1` only if it embeds evidence phases

**Interfaces:**
- Consumes: guest evidence phases + `guest/shell-chrome.json`
- Produces: throw if missing `jobs.wsl.platform.mocked`, `jobs.workstation.quiet`, `shell.chrome`; throw if `shell-chrome.json` schema ≠ `winmint.shell.chrome/v1` or `wallpaperPath` ≠ WinMint-Bloom path; throw if start/taskbar pin arrays omit Explorer/Terminal

- [ ] **Step 1: Write a red fixture test** — copy fixture, delete `shell-chrome.json`, run `Assert-SmokeEvidence.ps1 -StaticEvidenceOnly`; expect non-zero and message `shell-chrome.json`.

- [ ] **Step 2: Run — expect FAIL** (assert does not look for the file yet)

- [ ] **Step 3: Implement assert gates + update the happy fixture so existing S4 test still exits 0.**

`shell-chrome.json` fixture:

```json
{
  "schemaVersion": "winmint.shell.chrome/v1",
  "wallpaperPath": "C:\\Windows\\Web\\Wallpaper\\Windows\\WinMint-Bloom.jpg",
  "startPinIds": ["explorer", "settings", "terminal", "zen-browser", "cursor"],
  "taskbarPinIds": ["explorer", "terminal", "zen-browser", "cursor"],
  "quietDwords": { "SearchboxTaskbarMode": 0, "TaskbarDa": 0, "TaskbarMn": 0, "ShowTaskViewButton": 0, "ShowCopilotButton": 0 }
}
```

Smoke pull: if `Invoke-Smoke.ps1` copies `%ProgramData%\WinMint\*.json`, ensure `shell-chrome.json` is included the same way as `native-packages.json`.

- [ ] **Step 4: `just check`**

- [ ] **Step 5: Commit**

```bash
git commit -m "test(smoke): require mocked WSL and shell-chrome evidence"
```

---

## Spec coverage

| Spec item | Task |
|-----------|------|
| ProductPosture v1 groups + WhatsApp; preserve Clock; sl7 drop Alarms/YourPhone | 1 |
| Bloom stage / fail Apply if missing | 2 |
| Quiet DWords / Recycle Bin / CDM | 3 |
| Guest detect; no HypervisorPresent; WSL mock + distro skip; Terminal mock best-effort | 4 |
| Safety net live verify | 5 |
| `shell.chrome` job, SPI, ConfigureStartPins, LayoutModification, evidence, selected apps required on Complete | 6 |
| Fail-open baseline chrome | 7 |
| Smoke phases + `shell-chrome.json` | 8 |
| Cursors / XDG / Windhawk / Outlook UScheduler / this Failed VM | out of scope |

## Type names (do not drift)

- `HypervisorGuest.IsGuest(string? manufacturer, string? model, bool hyperVGuestKeyExists)`
- `IGuestMachine.IsHypervisorGuest()`
- `IGuestMachine.ApplyShellChrome(ShellChromeRequest request)` → `bool` (true = applied enough for this path)
- `ShellChromeRequest(bool FailOpen, IReadOnlyList<string> SelectedWingetIds)`
- `ProvisionJobKind.ShellChrome` / wire `shell.chrome`
- Phases: `jobs.wsl.platform.mocked`, `jobs.wsl.{id}.mocked`, `shell.chrome`
- Evidence schema: `winmint.shell.chrome/v1`
