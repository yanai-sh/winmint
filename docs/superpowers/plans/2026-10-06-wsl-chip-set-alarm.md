# WSL chip set + Arch via ALARM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wizard WSL chips are Fedora (default), Ubuntu, NixOS, and Arch-as-ALARM (`fromFile`); drop Pengwin and official `archlinux`.

**Architecture:** Catalog owns install truth. Retarget the Arch chip key to a new `fromFile` entry (`archlinuxarm-wsl` → `artiga033/archlinuxarm-wsl`, arm64-only). Harden GitHub release asset pick to prefer `*.wsl` when `Contains` matches multiple assets. CuratedDefaults stays Fedora. No Wizard arch-aware chip filter — plan fail-closes unsupported arch (existing ADR-010 gate).

**Tech Stack:** .NET 11 / C#, `config/packages.json` (embedded), xUnit host tests, WSL `fromFile` provisioning path.

## Global Constraints

- Spec: [docs/superpowers/specs/2026-10-06-wsl-chip-set-alarm-design.md](../specs/2026-10-06-wsl-chip-set-alarm-design.md)
- Chips exactly: Fedora (`FedoraLinux`), Ubuntu (`Ubuntu`), NixOS (`NixOS-WSL`), Arch (`archlinuxarm-wsl`).
- `CuratedDefaults.WslTokens` remains `["FedoraLinux"]`; do not seed Arch.
- Drop catalog + chip entries for `pengwin` and store `archlinux`.
- ALARM: `installKind` `fromFile`, `repo` `artiga033/archlinuxarm-wsl`, `installId` `archlinuxarm`, `architectures` `["arm64"]` only, arm64 asset candidates `["archlinuxarm-aarch64"]`.
- Prefer release assets whose name ends with `.wsl` (not `.wsl.bundle` / `.SHA256`) among `Contains` matches.
- Chip key = profile token = catalog key `archlinuxarm-wsl` (UI label still `Arch`).
- No `winmint.profile/v1` bump; no CONTEXT/ADR unless a coined polarity changes (it does not).
- Ponytail: no new abstractions beyond a small static asset picker if needed for tests; no amd64 official Arch dual path.
- Commit style: `docs:` · `feat(scope):` · `fix(scope):` …
- Focused tests while iterating; `just check` before final task commit.
- Work on current branch; commit when a task’s Commit step says so (skip commits if the human says not to).

## File map

| File | Responsibility |
|------|----------------|
| `config/packages.json` | WSL catalog rows (source of truth; embedded into Orchestrator) |
| `src/WinMint.Orchestrator/PackageCatalog.cs` | `CuratedPackageChips.Wsl` chip vocabulary |
| `src/WinMint.Provisioning/GitHubAssetDownload.cs` | Latest-release asset match + prefer `*.wsl` |
| `src/WinMint.Wizard/Views/SoftwareStepView.axaml` | Advanced WSL watermark examples |
| `tests/WinMint.Tests/WslJobsTests.cs` | Plan fromFile metadata + amd64 reject for ALARM |
| `tests/WinMint.Tests/GitHubAssetDownloadTests.cs` | Asset preference unit tests (new) |
| `tests/WinMint.Tests/PackageCatalogTests.cs` or chip test | Chip set / resolve ALARM token if needed |
| `docs/superpowers/specs/2026-10-06-wsl-chip-set-alarm-design.md` | Mark status accepted after land (optional docs commit) |

---

### Task 1: Catalog + chips — four WSL options, ALARM Arch

**Files:**
- Modify: `config/packages.json` (`wslDistros` block)
- Modify: `src/WinMint.Orchestrator/PackageCatalog.cs` (`CuratedPackageChips.Wsl`)
- Modify: `src/WinMint.Wizard/Views/SoftwareStepView.axaml` (Advanced WSL watermark)
- Test: `tests/WinMint.Tests/WslJobsTests.cs`
- Test: `tests/WinMint.Tests/PackageCatalogTests.cs` (optional assert on chip keys if you add one)

**Interfaces:**
- Consumes: existing `WslDistroEntry` / `fromFile` planning in `BuildPlan.PlanPackages`
- Produces:
  - Catalog key `archlinuxarm-wsl` with `InstallKind.FromFile`, `FromFileRepo = "artiga033/archlinuxarm-wsl"`, `InstallId = "archlinuxarm"`, arm64 assets `["archlinuxarm-aarch64"]`, `Architectures = ["arm64"]`
  - `CuratedPackageChips.Wsl` keys: `Ubuntu`, `FedoraLinux`, `archlinuxarm-wsl`, `NixOS-WSL` (order: Ubuntu, Fedora, Arch, NixOS — or Fedora, Ubuntu, Arch, NixOS; prefer **Fedora, Ubuntu, Arch, NixOS** to put default first)
  - No `pengwin`, no store `archlinux`

- [ ] **Step 1: Write failing plan tests**

Add to `tests/WinMint.Tests/WslJobsTests.cs`:

```csharp
[Fact]
public void Plan_archlinuxarm_wsl_emits_fromFile_metadata_on_arm64()
{
    Profile profile = Parse(MinimalJson(wsl: ["archlinuxarm-wsl"]));

    Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
        profile,
        new RunOptions { ImageArchitecture = "arm64" });

    Assert.True(result.IsOk);
    ProvisionJob arch = Assert.Single(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.Wsl);
    Assert.Equal("archlinuxarm", arch.PackageId);
    Assert.Equal(WslInstallKind.FromFile, arch.WslInstallKind);
    Assert.Equal("artiga033/archlinuxarm-wsl", arch.WslFromFileRepo);
    Assert.Contains("archlinuxarm-aarch64", arch.WslFromFileAssetNames!);
}

[Fact]
public void Plan_archlinuxarm_wsl_rejects_amd64_image()
{
    Profile profile = Parse(MinimalJson(wsl: ["archlinuxarm-wsl"]));

    Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
        profile,
        new RunOptions { ImageArchitecture = "amd64" });

    Assert.False(result.IsOk);
    Assert.Equal("packages.catalog.unsupportedArch", result.Error.Code);
}

[Fact]
public void Curated_wsl_chips_are_fedora_ubuntu_arch_nixos()
{
    string[] keys = [.. CuratedPackageChips.Wsl.Select(c => c.Key)];
    Assert.Equal(["FedoraLinux", "Ubuntu", "archlinuxarm-wsl", "NixOS-WSL"], keys);
}
```

(If `CuratedPackageChips` is not already imported via `WinMint.Orchestrator`, add the using.)

- [ ] **Step 2: Run tests — expect fail**

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~WslJobsTests.Plan_archlinuxarm|FullyQualifiedName~WslJobsTests.Curated_wsl"
```

Expected: FAIL (unknown token / old chip list).

- [ ] **Step 3: Update `config/packages.json` `wslDistros`**

Replace the `wslDistros` object with:

```json
  "wslDistros": {
    "Ubuntu": {
      "displayName": "Ubuntu",
      "installKind": "store",
      "installId": "Ubuntu",
      "architectures": ["amd64", "arm64"]
    },
    "FedoraLinux": {
      "displayName": "Fedora",
      "installKind": "store",
      "installId": "FedoraLinux",
      "architectures": ["amd64", "arm64"]
    },
    "archlinuxarm-wsl": {
      "displayName": "Arch",
      "installKind": "fromFile",
      "installId": "archlinuxarm",
      "repo": "artiga033/archlinuxarm-wsl",
      "assets": {
        "arm64": ["archlinuxarm-aarch64"]
      },
      "architectures": ["arm64"]
    },
    "NixOS-WSL": {
      "displayName": "NixOS",
      "installKind": "fromFile",
      "installId": "NixOS",
      "repo": "nix-community/NixOS-WSL",
      "assets": {
        "arm64": ["nixos.aarch64.wsl", "nixos.arm64.wsl", "nixos.wsl"],
        "amd64": ["nixos.wsl", "nixos.x86_64.wsl", "nixos.amd64.wsl"]
      },
      "architectures": ["amd64", "arm64"]
    }
  }
```

Remove `archlinux` and `pengwin` entirely.

- [ ] **Step 4: Update `CuratedPackageChips.Wsl`**

In `src/WinMint.Orchestrator/PackageCatalog.cs`:

```csharp
    public static IReadOnlyList<CuratedChipDefinition> Wsl { get; } =
    [
        new("FedoraLinux", "Fedora"),
        new("Ubuntu", "Ubuntu"),
        new("archlinuxarm-wsl", "Arch"),
        new("NixOS-WSL", "NixOS"),
    ];
```

- [ ] **Step 5: Update Advanced watermark**

In `SoftwareStepView.axaml`, set WSL watermark to:

`FedoraLinux&#x0A;archlinuxarm-wsl&#x0A;NixOS-WSL`

- [ ] **Step 6: Run tests — expect pass**

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~WslJobsTests"
```

Expected: PASS (including existing NixOS/Ubuntu cases). Also run curated defaults:

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~CuratedDefaultsTests"
```

Expected: PASS — still Fedora-only seed.

- [ ] **Step 7: Commit**

```powershell
git add config/packages.json src/WinMint.Orchestrator/PackageCatalog.cs src/WinMint.Wizard/Views/SoftwareStepView.axaml tests/WinMint.Tests/WslJobsTests.cs
git commit -m "$(cat <<'EOF'
feat(packages): WSL chips Fedora/Ubuntu/Arch(ALARM)/NixOS

Drop Pengwin and official archlinux; Arch chip is arm64 fromFile ALARM.
EOF
)"
```

---

### Task 2: Prefer `*.wsl` when matching GitHub release assets

**Files:**
- Modify: `src/WinMint.Provisioning/GitHubAssetDownload.cs`
- Create: `tests/WinMint.Tests/GitHubAssetDownloadTests.cs`

**Interfaces:**
- Consumes: latest-release JSON asset list
- Produces: `GitHubAssetDownload.PickReleaseAsset(IEnumerable<(string Name, string? Url)> assets, IReadOnlyList<string> candidates)` (or equivalent internal/public static) returning the chosen name/url; download method uses it

- [ ] **Step 1: Write failing picker tests**

```csharp
using WinMint.Provisioning;

namespace WinMint.Tests;

public class GitHubAssetDownloadTests
{
    [Fact]
    public void PickReleaseAsset_prefers_wsl_over_bundle_and_sha()
    {
        (string Name, string? Url)[] assets =
        [
            ("archlinuxarm-aarch64-2026.10.01.wsl.bundle", "https://example/bundle"),
            ("archlinuxarm-aarch64-2026.10.01.wsl.SHA256", "https://example/sha"),
            ("archlinuxarm-aarch64-2026.10.01.wsl", "https://example/wsl"),
        ];

        (string Name, string Url)? picked = GitHubAssetDownload.PickReleaseAsset(
            assets,
            ["archlinuxarm-aarch64"]);

        Assert.NotNull(picked);
        Assert.Equal("archlinuxarm-aarch64-2026.10.01.wsl", picked.Value.Name);
        Assert.Equal("https://example/wsl", picked.Value.Url);
    }

    [Fact]
    public void PickReleaseAsset_skips_path_traversal_names()
    {
        (string Name, string? Url)[] assets =
        [
            ("../evil.wsl", "https://example/evil"),
            ("archlinuxarm-aarch64.wsl", "https://example/ok"),
        ];

        (string Name, string Url)? picked = GitHubAssetDownload.PickReleaseAsset(
            assets,
            ["archlinuxarm-aarch64"]);

        Assert.NotNull(picked);
        Assert.Equal("archlinuxarm-aarch64.wsl", picked.Value.Name);
    }
}
```

If `PickReleaseAsset` is `internal`, use `InternalsVisibleTo` already present for tests, or make the method `public` for the seam (prefer `internal` + existing test friend).

- [ ] **Step 2: Run test — expect fail**

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~GitHubAssetDownloadTests"
```

Expected: FAIL (method missing).

- [ ] **Step 3: Implement picker + wire download**

In `GitHubAssetDownload.cs`, add:

```csharp
    internal static (string Name, string Url)? PickReleaseAsset(
        IEnumerable<(string Name, string? BrowserDownloadUrl)> assets,
        IReadOnlyList<string> assetNameCandidates)
    {
        foreach (string candidate in assetNameCandidates)
        {
            List<(string Name, string Url)> matches = [];
            foreach ((string name, string? url) in assets)
            {
                if (string.IsNullOrWhiteSpace(url))
                {
                    continue;
                }

                string leaf = Path.GetFileName(name);
                if (string.IsNullOrWhiteSpace(leaf)
                    || !string.Equals(leaf, name, StringComparison.Ordinal))
                {
                    continue;
                }

                if (!name.Contains(candidate, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                matches.Add((name, url));
            }

            (string Name, string Url)? preferred = matches
                .Where(m => m.Name.EndsWith(".wsl", StringComparison.OrdinalIgnoreCase))
                .Select(m => ((string Name, string Url)?)m)
                .FirstOrDefault();
            if (preferred is not null)
            {
                return preferred;
            }

            if (matches.Count > 0)
            {
                return matches[0];
            }
        }

        return null;
    }
```

Refactor `TryDownloadGitHubReleaseAssetAsync` to call `PickReleaseAsset` on `release.Assets.Select(a => (a.Name, a.BrowserDownloadUrl))` instead of inline `FirstOrDefault` + `Contains`.

- [ ] **Step 4: Run tests — expect pass**

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~GitHubAssetDownloadTests|FullyQualifiedName~WslJobsTests"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add src/WinMint.Provisioning/GitHubAssetDownload.cs tests/WinMint.Tests/GitHubAssetDownloadTests.cs
git commit -m "$(cat <<'EOF'
fix(provisioning): prefer .wsl assets for fromFile WSL downloads

Avoid matching .wsl.bundle / .SHA256 when Contains is ambiguous.
EOF
)"
```

---

### Task 3: Gate green + spec status

**Files:**
- Modify: `docs/superpowers/specs/2026-10-06-wsl-chip-set-alarm-design.md` (status → accepted)
- Verify: no leftover `pengwin` / store `archlinux` references in product chips/catalog

- [ ] **Step 1: Grep for leftovers**

```powershell
rg -n "pengwin|\"archlinux\"" config/packages.json src/WinMint.Orchestrator/PackageCatalog.cs
```

Expected: no product chip/catalog hits (tests/docs/history OK).

- [ ] **Step 2: Run full check**

```powershell
just check
```

Expected: green.

- [ ] **Step 3: Mark spec accepted + commit**

In the design spec header, set `Status: accepted`.

```powershell
git add docs/superpowers/specs/2026-10-06-wsl-chip-set-alarm-design.md docs/superpowers/plans/2026-10-06-wsl-chip-set-alarm.md
git commit -m "docs: accept WSL chip set + ALARM Arch plan"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Four chips Fedora/Ubuntu/NixOS/Arch | Task 1 |
| Fedora remains curated default | Task 1 (no CuratedDefaults change; CuratedDefaultsTests) |
| Arch = ALARM fromFile arm64 | Task 1 |
| Drop Pengwin + official archlinux | Task 1 |
| Prefer `*.wsl` asset | Task 2 |
| amd64 rejects Arch | Task 1 |
| `just check` green | Task 3 |
