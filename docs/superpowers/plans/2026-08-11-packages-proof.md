# Packages Proof Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Prefer ponytail / YAGNI on every task. Use verification-before-completion before any “done” claim.

**Goal:** Prove every live winget/scoop catalog id (plus ProductPosture constants) via host dry-run/download, commit `config/packages.proof.json`, and fail `just check` offline when that receipt is missing or stale.

**Architecture:** Extend `Invoke-PackagesCheck.ps1` to the installability proof bar and atomically write a content-hash receipt. Add a small Orchestrator `PackagesProof` helper that recomputes the same hashes for an offline xUnit gate. Network prove stays out of the `just check` recipe body.

**Tech Stack:** C# (.NET / xUnit), pwsh 7.6+, winget App Installer, HTTP for scoop manifests/archives, `just`.

**Spec:** [2026-08-11-packages-proof-design.md](../specs/2026-08-11-packages-proof-design.md)

## Global Constraints

```
- ARM64-first prove default; host must be native ARM64 with winget on PATH for `just packages-check`.
- `just check` stays offline — only the receipt unit test runs there.
- Stubs (`stub: true`) are skipped by prove and must not be ProductPosture / live Plan defaults.
- ProductPosture winget/scoop constants must exist as non-stub catalog rows.
- On prove failure: do not overwrite `config/packages.proof.json`.
- No Hyper-V prove, no Store prove, no time-based expiry (this plan).
- Commit when the user asks (or at task end if they chose execution with commits).
- Keep `just check` green after each task that can be green offline; Task 4 intentionally needs a real receipt from Task 3.
```

## File map

| File | Responsibility |
|------|----------------|
| `src/WinMint.Orchestrator/PackageCatalog.cs` | Parse `stub`; expose `IsStub` on `PackageToolEntry` |
| `src/WinMint.Orchestrator/PackagesProof.cs` | Prove-set + SHA-256 + receipt validate (offline) |
| `tests/WinMint.Tests/PackagesProofTests.cs` | Temp-dir hash/validate tests + repo receipt gate |
| `tools/host/Invoke-PackagesCheck.ps1` | Dry-run / scoop download prove; write receipt |
| `Justfile` | `packages-check` always full prove; drop weak PROBE default |
| `config/packages.proof.json` | Committed receipt (created by prover) |
| `docs/decisions/ADR-010-arm64-package-policy.md` | Amend catalog-time truth language |
| `docs/specs/2026-08-05-package-catalog-arm64.md` | Point maintainers at prove + receipt |
| `docs/superpowers/specs/2026-08-11-packages-proof-design.md` | Link Plan path |

---

### Task 1: Stub field + `PackagesProof` + offline tests

**Files:**
- Modify: `src/WinMint.Orchestrator/PackageCatalog.cs` (`PackageToolDto`, `PackageToolEntry`, `Build`)
- Create: `src/WinMint.Orchestrator/PackagesProof.cs`
- Create: `tests/WinMint.Tests/PackagesProofTests.cs`
- Modify: `tests/WinMint.Tests/PackageCatalogValidatorTests.cs` (optional assert FancyWM stub)

**Interfaces:**
- Consumes: `PackageCatalog`, `PackageToolEntry`, `ProductPosture.WingetIds` / `ScoopIds`
- Produces:
  - `PackageToolEntry.IsStub` (`bool`)
  - `PackagesProof.CatalogSha256(string catalogPath) -> string` (lowercase hex)
  - `PackagesProof.BuildProveSet(PackageCatalog catalog, string architecture) -> IReadOnlyList<PackagesProofEntry>`
  - `PackagesProof.ProveSetSha256(IReadOnlyList<PackagesProofEntry> entries) -> string`
  - `PackagesProof.ValidateReceipt(string receiptPath, string catalogPath, PackageCatalog catalog, string architecture) -> IReadOnlyList<string>` (empty = ok)
  - `record PackagesProofEntry(string Source, string Id, string? ScoopBucket)`

- [ ] **Step 1: Write failing tests for prove-set + hash + validate**

Create `tests/WinMint.Tests/PackagesProofTests.cs`:

```csharp
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class PackagesProofTests
{
    [Fact]
    public void BuildProveSet_skips_stubs_and_requires_product_constants()
    {
        string dir = NewTemp();
        try
        {
            string catalogPath = Path.Combine(dir, "packages.json");
            File.WriteAllText(catalogPath, """
                {
                  "tools": {
                    "live": {
                      "displayName": "Live",
                      "source": "winget",
                      "id": "Contoso.Live",
                      "architectures": ["arm64"]
                    },
                    "soon": {
                      "displayName": "Soon",
                      "source": "winget",
                      "id": "Contoso.Soon",
                      "stub": true,
                      "architectures": ["arm64"]
                    }
                  }
                }
                """);

            PackageCatalog catalog = PackageCatalog.TryLoadFromFile(catalogPath).Value;
            // Without ProductPosture constants in this tiny catalog, BuildProveSet must surface errors
            // via ValidateProductConstants — see next asserts on full Default catalog.
            IReadOnlyList<PackagesProofEntry> set = PackagesProof.BuildProveSet(catalog, "arm64");
            Assert.Contains(set, e => e.Id == "Contoso.Live" && e.Source == "winget");
            Assert.DoesNotContain(set, e => e.Id == "Contoso.Soon");
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void ProveSetSha256_is_stable_sorted_source_id_lines()
    {
        IReadOnlyList<PackagesProofEntry> entries =
        [
            new("scoop", "starship", "main"),
            new("winget", "Git.MinGit", null),
        ];
        // Intentionally unsorted input; hash must match sorted "scoop:starship\nwinget:Git.MinGit\n"
        string expected = Convert.ToHexString(
            SHA256.HashData(Encoding.UTF8.GetBytes("scoop:starship\nwinget:Git.MinGit\n")))
            .ToLowerInvariant();
        Assert.Equal(expected, PackagesProof.ProveSetSha256(entries));
    }

    [Fact]
    public void ValidateReceipt_detects_catalog_hash_mismatch()
    {
        string dir = NewTemp();
        try
        {
            string catalogPath = Path.Combine(dir, "packages.json");
            File.WriteAllText(catalogPath, """
                {"tools":{"a":{"displayName":"A","source":"winget","id":"A.A","architectures":["arm64"]}}}
                """);
            PackageCatalog catalog = PackageCatalog.TryLoadFromFile(catalogPath).Value;
            string receiptPath = Path.Combine(dir, "packages.proof.json");
            File.WriteAllText(receiptPath, """
                {
                  "schema": "winmint.packages.proof/v1",
                  "architecture": "arm64",
                  "catalogSha256": "deadbeef",
                  "proveSetSha256": "deadbeef",
                  "provenAtUtc": "2026-08-11T00:00:00Z",
                  "host": { "winget": "test", "osArch": "ARM64" },
                  "entries": [ { "source": "winget", "id": "A.A", "method": "winget-install-dry-run" } ]
                }
                """);

            IReadOnlyList<string> errors = PackagesProof.ValidateReceipt(
                receiptPath, catalogPath, catalog, "arm64");
            Assert.Contains(errors, e => e.Contains("catalogSha256", StringComparison.Ordinal));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void Default_catalog_product_constants_are_non_stub_rows()
    {
        IReadOnlyList<string> missing = PackagesProof.MissingProductConstants(PackageCatalog.Default);
        Assert.Empty(missing);
    }

    [Fact]
    public void Repo_packages_proof_matches_catalog()
    {
        string root = FindRepoRoot();
        string catalogPath = Path.Combine(root, "config", "packages.json");
        string receiptPath = Path.Combine(root, "config", "packages.proof.json");
        Assert.True(
            File.Exists(receiptPath),
            "Missing config/packages.proof.json — run: just packages-check");

        PackageCatalog catalog = PackageCatalog.TryLoadFromFile(catalogPath).Value;
        IReadOnlyList<string> errors = PackagesProof.ValidateReceipt(
            receiptPath, catalogPath, catalog, "arm64");
        Assert.True(errors.Count == 0, string.Join(Environment.NewLine, errors));
    }

    private static string NewTemp() =>
        Directory.CreateDirectory(
            Path.Combine(Path.GetTempPath(), "winmint-proof-" + Guid.NewGuid().ToString("N")))
            .FullName;

    private static string FindRepoRoot()
    {
        DirectoryInfo? dir = new(AppContext.BaseDirectory);
        while (dir is not null)
        {
            if (File.Exists(Path.Combine(dir.FullName, "config", "packages.json")))
            {
                return dir.FullName;
            }

            dir = dir.Parent;
        }

        throw new InvalidOperationException("repo root not found");
    }
}
```

Note: until Task 3/4 land a real receipt, `Repo_packages_proof_matches_catalog` will fail — that is the gate. Keep it; do not skip. For local iteration on Task 1 only, implement `PackagesProof` so temp tests pass; expect the repo gate red until Task 4.

- [ ] **Step 2: Run tests — expect compile/API failures**

Run:

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~PackagesProofTests"
```

Expected: FAIL (types/methods missing).

- [ ] **Step 3: Add `stub` to catalog model**

In `PackageToolDto` add:

```csharp
[JsonPropertyName("stub")]
public bool Stub { get; set; }
```

Extend `PackageToolEntry`:

```csharp
public sealed record PackageToolEntry(
    string CatalogKey,
    string DisplayName,
    PackageToolSource Source,
    string InstallId,
    IReadOnlyList<string> Architectures,
    string? ScoopBucket = null,
    bool IsStub = false);
```

Pass `dto.Stub` from `Build`.

- [ ] **Step 4: Implement `PackagesProof.cs`**

```csharp
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Orchestrator;

public sealed record PackagesProofEntry(string Source, string Id, string? ScoopBucket);

public static class PackagesProof
{
    public const string Schema = "winmint.packages.proof/v1";
    public const string DefaultArchitecture = "arm64";

    public static string CatalogSha256(string catalogPath)
    {
        byte[] bytes = File.ReadAllBytes(catalogPath);
        return Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    }

    public static IReadOnlyList<string> MissingProductConstants(PackageCatalog catalog)
    {
        List<string> missing = [];
        foreach (string id in ProductPosture.WingetIds)
        {
            if (!catalog.TryGetToolByInstallId(id, out PackageToolEntry? tool)
                || tool.Source is not PackageToolSource.Winget
                || tool.IsStub)
            {
                missing.Add($"winget:{id}");
            }
        }

        foreach (string id in ProductPosture.ScoopIds)
        {
            if (!catalog.TryGetToolByInstallId(id, out PackageToolEntry? tool)
                || tool.Source is not PackageToolSource.Scoop
                || tool.IsStub)
            {
                missing.Add($"scoop:{id}");
            }
        }

        return missing;
    }

    public static IReadOnlyList<PackagesProofEntry> BuildProveSet(
        PackageCatalog catalog,
        string architecture)
    {
        string arch = PackageCatalog.NormalizeArch(architecture);
        List<PackagesProofEntry> list = [];
        foreach (string key in catalog.ToolCatalogKeys)
        {
            if (!catalog.TryGetToolByKey(key, out PackageToolEntry? tool) || tool.IsStub)
            {
                continue;
            }

            if (tool.Architectures.Count > 0
                && !tool.Architectures.Any(a => string.Equals(a, arch, StringComparison.OrdinalIgnoreCase)))
            {
                continue;
            }

            if (tool.Source is PackageToolSource.Winget)
            {
                list.Add(new PackagesProofEntry("winget", tool.InstallId, null));
            }
            else if (tool.Source is PackageToolSource.Scoop)
            {
                list.Add(new PackagesProofEntry(
                    "scoop",
                    tool.InstallId,
                    tool.ScoopBucket ?? "main"));
            }
            // store / other: skip
        }

        return list
            .OrderBy(e => e.Source, StringComparer.Ordinal)
            .ThenBy(e => e.Id, StringComparer.Ordinal)
            .ToArray();
    }

    public static string ProveSetSha256(IReadOnlyList<PackagesProofEntry> entries)
    {
        IOrderedEnumerable<PackagesProofEntry> ordered = entries
            .OrderBy(e => e.Source, StringComparer.Ordinal)
            .ThenBy(e => e.Id, StringComparer.Ordinal);
        StringBuilder sb = new();
        foreach (PackagesProofEntry e in ordered)
        {
            sb.Append(e.Source).Append(':').Append(e.Id).Append('\n');
        }

        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(sb.ToString())))
            .ToLowerInvariant();
    }

    public static IReadOnlyList<string> ValidateReceipt(
        string receiptPath,
        string catalogPath,
        PackageCatalog catalog,
        string architecture)
    {
        List<string> errors = [];
        foreach (string m in MissingProductConstants(catalog))
        {
            errors.Add($"product constant missing or stub in catalog: {m}");
        }

        if (!File.Exists(receiptPath))
        {
            errors.Add("Missing config/packages.proof.json — run: just packages-check");
            return errors;
        }

        PackagesProofFile? doc;
        try
        {
            doc = JsonSerializer.Deserialize<PackagesProofFile>(
                File.ReadAllText(receiptPath),
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        }
        catch (Exception ex)
        {
            errors.Add($"packages.proof.json parse failed: {ex.Message}");
            return errors;
        }

        if (doc is null || !string.Equals(doc.Schema, Schema, StringComparison.Ordinal))
        {
            errors.Add($"packages.proof.json schema must be {Schema}");
        }

        string arch = PackageCatalog.NormalizeArch(architecture);
        if (!string.Equals(doc?.Architecture, arch, StringComparison.OrdinalIgnoreCase))
        {
            errors.Add($"packages.proof.json architecture must be {arch}");
        }

        string catalogHash = CatalogSha256(catalogPath);
        if (!string.Equals(doc?.CatalogSha256, catalogHash, StringComparison.OrdinalIgnoreCase))
        {
            errors.Add("catalogSha256 mismatch — run: just packages-check");
        }

        IReadOnlyList<PackagesProofEntry> proveSet = BuildProveSet(catalog, arch);
        string proveHash = ProveSetSha256(proveSet);
        if (!string.Equals(doc?.ProveSetSha256, proveHash, StringComparison.OrdinalIgnoreCase))
        {
            errors.Add("proveSetSha256 mismatch — run: just packages-check");
        }

        HashSet<string> receiptIds = new(StringComparer.OrdinalIgnoreCase);
        foreach (PackagesProofEntryDto? e in doc?.Entries ?? [])
        {
            if (e?.Source is null || e.Id is null)
            {
                continue;
            }

            receiptIds.Add($"{e.Source.ToLowerInvariant()}:{e.Id}");
        }

        foreach (PackagesProofEntry required in proveSet)
        {
            string key = $"{required.Source}:{required.Id}";
            if (!receiptIds.Contains(key))
            {
                errors.Add($"receipt missing entry {key} — run: just packages-check");
            }
        }

        return errors;
    }

    private sealed class PackagesProofFile
    {
        [JsonPropertyName("schema")]
        public string? Schema { get; set; }

        [JsonPropertyName("architecture")]
        public string? Architecture { get; set; }

        [JsonPropertyName("catalogSha256")]
        public string? CatalogSha256 { get; set; }

        [JsonPropertyName("proveSetSha256")]
        public string? ProveSetSha256 { get; set; }

        [JsonPropertyName("entries")]
        public List<PackagesProofEntryDto>? Entries { get; set; }
    }

    private sealed class PackagesProofEntryDto
    {
        [JsonPropertyName("source")]
        public string? Source { get; set; }

        [JsonPropertyName("id")]
        public string? Id { get; set; }
    }
}
```

If `PackageCatalog.NormalizeArch` is not public, either make it `public`/`internal` visible to tests via InternalsVisibleTo (already likely) or duplicate the tiny normalize in `PackagesProof` as a private helper matching catalog rules (`x64`→`amd64`, lower). Prefer exposing/using the existing helper.

Also fix the temp catalog test: it only asserts stub skip; `MissingProductConstants(PackageCatalog.Default)` covers constants. Remove the misleading comment in Step 1 if you slim that test to stub-skip only.

- [ ] **Step 5: Run temp tests (repo gate may still fail)**

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~PackagesProofTests"
```

Expected: temp/hash/constant tests PASS; `Repo_packages_proof_matches_catalog` FAIL with missing receipt (acceptable until Task 4).

- [ ] **Step 6: Commit (if execution includes commits)**

```powershell
git add src/WinMint.Orchestrator/PackageCatalog.cs src/WinMint.Orchestrator/PackagesProof.cs tests/WinMint.Tests/PackagesProofTests.cs
git commit -m "feat(packages): offline packages.proof validator and stub field"
```

---

### Task 2: Upgrade `Invoke-PackagesCheck.ps1` to dry-run prove + receipt

**Files:**
- Modify: `tools/host/Invoke-PackagesCheck.ps1`
- Modify: `Justfile` (`packages-check` recipe)

**Interfaces:**
- Consumes: `config/packages.json`; prove set rules matching `PackagesProof.BuildProveSet`
- Produces: `config/packages.proof.json` with schema `winmint.packages.proof/v1`
- Hash rules (must match C#):
  - `catalogSha256` = SHA256 of **raw file bytes**, lowercase hex
  - `proveSetSha256` = SHA256 of UTF-8 text of sorted `source:id\n` lines (Ordinal sort by source then id), lowercase hex
  - Sources in prove set / receipt: lowercase `winget` / `scoop` only

- [ ] **Step 1: Replace winget show with dry-run**

Replace `Test-WingetId` body with:

```powershell
function Test-WingetId {
    param(
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][string] $Architecture
    )
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        throw 'winget not on PATH (install App Installer / use an ARM64 host with winget)'
    }
    $out = & winget install --id $Id --exact --architecture $Architecture --dry-run `
        --disable-interactivity --accept-package-agreements --accept-source-agreements 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $tail = ($out | Out-String).Trim()
        if ($tail.Length -gt 240) { $tail = $tail.Substring(0, 240) + '…' }
        throw "winget install --dry-run failed (exit $code): $tail"
    }
}
```

Call `winget source update` once at start of `Invoke-PackagesCheck` (best-effort; log and continue if non-zero only if dry-runs still succeed — prefer fail if update fails hard).

- [ ] **Step 2: Scoop prove = manifest + download to temp**

Keep manifest fetch + arm64 URL extraction. Always download (remove `-ProbeScoopUrls` as optional weak mode):

```powershell
function Test-ScoopId {
    param(
        [Parameter(Mandatory)][string] $Id,
        [string] $Bucket,
        [Parameter(Mandatory)][string] $Architecture
    )
    $uri = Get-ScoopManifestUri -Id $Id -Bucket $Bucket
    $manifest = Invoke-RestMethod -Uri $uri -Method Get
    $url = Test-ScoopArm64Url -Manifest $manifest
    if ($Architecture -eq 'arm64' -and [string]::IsNullOrWhiteSpace($url)) {
        throw "scoop manifest has no arm64/aarch64 (or universal) url: $uri"
    }
    if ([string]::IsNullOrWhiteSpace($url)) {
        throw "scoop manifest has no download url: $uri"
    }
    # Manifest url may be string or array — take first
    if ($url -is [System.Array]) { $url = [string]$url[0] }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("winmint-scoop-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $dest = Join-Path $tmp 'payload.bin'
        Invoke-WebRequest -Uri ([string]$url) -OutFile $dest -MaximumRedirection 5
        if (-not (Test-Path -LiteralPath $dest) -or (Get-Item -LiteralPath $dest).Length -le 0) {
            throw "scoop download empty: $url"
        }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
```

- [ ] **Step 3: Host arch guard**

At start of `Invoke-PackagesCheck`:

```powershell
$osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
if ($Architecture -eq 'arm64' -and $osArch -ne 'Arm64') {
    throw "packages-check for arm64 requires native ARM64 host (OSArchitecture=$osArch)"
}
```

- [ ] **Step 4: Build prove entries + write receipt only on full success**

Collect successful entries in a list while iterating. On any failure, throw after the loop **without** writing the receipt.

Hash helpers:

```powershell
function Get-FileSha256Hex {
    param([Parameter(Mandatory)][string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ProveSetSha256Hex {
    param([Parameter(Mandatory)][object[]] $Entries)
    $lines = $Entries |
        Sort-Object @{ Expression = 'Source'; Ascending = $true }, @{ Expression = 'Id'; Ascending = $true } |
        ForEach-Object { "$($_.Source):$($_.Id)" }
    $text = ($lines -join "`n") + "`n"
    if ($Entries.Count -eq 0) { $text = '' }  # empty prove set → empty string hash; prefer always append newline only when Count>0 matching C#
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $sha = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return ([System.BitConverter]::ToString($sha) -replace '-', '').ToLowerInvariant()
}
```

**Critical:** C# builds `"scoop:starship\nwinget:Git.MinGit\n"` (trailing newline after each line including last). Match exactly — do not use a dangling empty line beyond that. For empty set, both sides use empty string → SHA256 of zero bytes.

After all ok:

```powershell
$receiptPath = Join-Path $repoRoot 'config\packages.proof.json'
$wingetVer = (& winget --version 2>$null | Out-String).Trim()
$receipt = [ordered]@{
    schema           = 'winmint.packages.proof/v1'
    architecture     = $arch
    catalogSha256    = Get-FileSha256Hex -Path $CatalogPath
    proveSetSha256   = Get-ProveSetSha256Hex -Entries $script:ProveEntries
    provenAtUtc      = [datetime]::UtcNow.ToString('o')
    host             = @{
        winget = $wingetVer
        osArch = $osArch
    }
    entries          = @($script:ProveEntries | ForEach-Object {
        $row = [ordered]@{
            source = $_.Source
            id     = $_.Id
            method = $_.Method
        }
        if ($_.Source -eq 'scoop') { $row.bucket = $_.Bucket }
        [pscustomobject]$row
    })
}
$tmpReceipt = Join-Path $repoRoot 'config\packages.proof.json.tmp'
($receipt | ConvertTo-Json -Depth 6) + "`n" | Set-Content -LiteralPath $tmpReceipt -Encoding utf8NoBOM
Move-Item -LiteralPath $tmpReceipt -Destination $receiptPath -Force
```

When recording an ok winget entry: `Source=winget`, `Method=winget-install-dry-run`. Scoop: `Method=scoop-manifest-download`, `Bucket=...`.

Skip stubs as today. Do **not** include stubs in `$script:ProveEntries`.

- [ ] **Step 5: Update synopsis / remove weak PROBE default**

- Drop `-ProbeScoopUrls` param (or leave unused and unused in Justfile — prefer delete).
- Update comment: validity = dry-run prove + receipt, not show-only.

- [ ] **Step 6: Justfile**

```just
# Maintainer: prove live winget/scoop ids (dry-run / download) + write config/packages.proof.json.
# Network + native ARM64 + winget. Not inlined into `just check` (offline receipt test enforces freshness).
packages-check ARCH="arm64":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/host/Invoke-PackagesCheck.ps1' -Architecture '{{ARCH}}'
```

- [ ] **Step 7: Extend `-SelfCheck`**

Keep existing URI/arm64 URL checks. Add:

```powershell
$entries = @(
    [pscustomobject]@{ Source = 'scoop'; Id = 'starship' },
    [pscustomobject]@{ Source = 'winget'; Id = 'Git.MinGit' }
)
$hash = Get-ProveSetSha256Hex -Entries $entries
# Must match C# PackagesProof.ProveSetSha256 for the same two entries — pin expected hex from a one-liner in Step 5 of Task 1 or compute once and hardcode.
```

Compute expected hex once with:

```powershell
dotnet run --project … 
```

Or paste the Assert from `ProveSetSha256_is_stable_sorted_source_id_lines` expected value into SelfCheck.

- [ ] **Step 8: Offline SelfCheck still green**

```powershell
pwsh -NoProfile -File tools/host/Invoke-PackagesCheck.ps1 -SelfCheck
```

Expected: `SelfCheck ok`

- [ ] **Step 9: Commit (if execution includes commits)**

```powershell
git add tools/host/Invoke-PackagesCheck.ps1 Justfile
git commit -m "feat(packages): dry-run packages-check writes packages.proof receipt"
```

---

### Task 3: Generate real `config/packages.proof.json` on ARM64

**Files:**
- Create: `config/packages.proof.json` (via prover)

**Interfaces:**
- Consumes: Task 2 script + current `config/packages.json`
- Produces: committed receipt that satisfies `PackagesProof.ValidateReceipt`

- [ ] **Step 1: Run full prove on native ARM64**

```powershell
just packages-check
```

Expected: all non-stub tools ok; `config/packages.proof.json` written; exit 0. If any id fails, fix catalog id/arch/bucket (or mark true future stubs) and rerun — do not hand-edit hashes.

- [ ] **Step 2: Verify offline gate**

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~PackagesProofTests"
just check
```

Expected: all PASS (including `Repo_packages_proof_matches_catalog`).

- [ ] **Step 3: Commit receipt (if execution includes commits)**

```powershell
git add config/packages.proof.json
git commit -m "chore(packages): commit packages.proof receipt from dry-run prove"
```

---

### Task 4: Docs sync

**Files:**
- Modify: `docs/decisions/ADR-010-arm64-package-policy.md`
- Modify: `docs/specs/2026-08-05-package-catalog-arm64.md`
- Modify: `docs/specs/2026-08-06-alpha-package-program.md` (Testing Decisions bullet)
- Modify: `docs/superpowers/specs/2026-08-11-packages-proof-design.md` (add Plan link)

- [ ] **Step 1: Amend ADR-010 decision §5**

Replace the show-only sentence with:

```markdown
5. **Architecture truth at catalog time:** `just packages-check` (`tools/host/Invoke-PackagesCheck.ps1`) proves live winget ids with `winget install --dry-run` and scoop ids via manifest + archive download, then writes `config/packages.proof.json`. `just check` validates that receipt offline (content-hash). Stubs (`stub: true`) are skipped. **`package.auditNative`** remains optional metal evidence — not default FirstLogon policy ([ADR-011](ADR-011-alpha-posture-and-package-delegation.md)).
```

Add amended date note (2026-08-11).

- [ ] **Step 2: Catalog + alpha package program docs**

In package-catalog maintenance section, require prove + commit receipt when editing `packages.json`.

In alpha-package-program Testing Decisions, replace “scoop manifest arm64 URL check” with dry-run prove + receipt gate.

- [ ] **Step 3: Link plan from design spec header**

```markdown
**Plan:** [2026-08-11-packages-proof.md](../plans/2026-08-11-packages-proof.md)
```

- [ ] **Step 4: Commit (if execution includes commits)**

```powershell
git add docs/decisions/ADR-010-arm64-package-policy.md docs/specs/2026-08-05-package-catalog-arm64.md docs/specs/2026-08-06-alpha-package-program.md docs/superpowers/specs/2026-08-11-packages-proof-design.md
git commit -m "docs: packages-check dry-run + packages.proof receipt gate"
```

---

## Spec coverage (self-review)

| Spec requirement | Task |
|------------------|------|
| Prove set = non-stub catalog ∩ arch ∪ ProductPosture constants | 1 (`MissingProductConstants` + `BuildProveSet`) |
| Stubs skipped / tentative only | 1–2 |
| Winget dry-run / scoop download | 2 |
| Receipt schema + hashes + atomic write | 2–3 |
| Offline `just check` fail closed | 1 (`Repo_packages_proof_matches_catalog`) |
| Not inlined into `just check` body | 2 Justfile |
| ADR / catalog docs | 4 |
| No Hyper-V / Store / time expiry | Non-goals — no tasks |

## Placeholder / consistency notes

- Prove-set line format is locked: `source:id\n` per entry, Ordinal sort by source then id, sources lowercase.
- `catalogSha256` is raw file bytes (PowerShell `Get-FileHash` / .NET `File.ReadAllBytes`) — do not normalize JSON before hashing.
- FancyWM remains `stub: true` and must not appear in receipt entries.
