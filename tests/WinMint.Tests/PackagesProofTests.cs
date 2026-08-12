using System.Security.Cryptography;
using System.Text;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class PackagesProofTests
{
    [Fact]
    public void BuildProveSet_skips_stubs()
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
    public void Validate_detects_catalog_hash_mismatch()
    {
        string dir = NewTemp();
        try
        {
            string catalogPath = Path.Combine(dir, "packages.json");
            File.WriteAllText(catalogPath, """
                {"tools":{"a":{"displayName":"A","source":"winget","id":"A.A","architectures":["arm64"]}}}
                """);
            PackageCatalog catalog = PackageCatalog.TryLoadFromFile(catalogPath).Value;
            string proofPath = Path.Combine(dir, "packages.proof.json");
            File.WriteAllText(proofPath, """
                {
                  "schemaVersion": "winmint.packages.proof/v1",
                  "architecture": "arm64",
                  "catalogSha256": "deadbeef",
                  "proveSetSha256": "deadbeef",
                  "provenAtUtc": "2026-08-11T00:00:00Z",
                  "host": { "winget": "test", "osArch": "ARM64" },
                  "entries": [ { "source": "winget", "id": "A.A", "method": "winget-install-dry-run" } ]
                }
                """);

            IReadOnlyList<string> errors = PackagesProof.Validate(
                proofPath, catalogPath, catalog, "arm64");
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
        string root = TestRepo.Root;
        string catalogPath = Path.Combine(root, "config", "packages.json");
        string proofPath = Path.Combine(root, "config", "packages.proof.json");
        Assert.True(
            File.Exists(proofPath),
            "Missing config/packages.proof.json — run: just packages-check");

        PackageCatalog catalog = PackageCatalog.TryLoadFromFile(catalogPath).Value;
        IReadOnlyList<string> errors = PackagesProof.Validate(
            proofPath, catalogPath, catalog, "arm64");
        Assert.True(errors.Count == 0, string.Join(Environment.NewLine, errors));
    }

    /// <summary>
    /// MinGit is the product constant; full Git for Windows carries an MSYS2 bash payload
    /// we never install. Offering it in the catalog is enough for a Profile to opt in.
    /// </summary>
    [Fact]
    public void Default_catalog_offers_MinGit_not_full_git()
    {
        Assert.False(PackageCatalog.Default.TryGetToolByInstallId("Git.Git", out _));
        Assert.True(PackageCatalog.Default.TryGetToolByInstallId(ProductPosture.MinGitWingetId, out _));
    }

    private static string NewTemp() =>
        Directory.CreateDirectory(
            Path.Combine(Path.GetTempPath(), "winmint-proof-" + Guid.NewGuid().ToString("N")))
            .FullName;

}
