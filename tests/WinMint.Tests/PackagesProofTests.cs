using System.Reflection;
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

    [Fact]
    public void BuildProveSet_filters_ineligible_entries_and_orders_source_then_id()
    {
        string dir = NewTemp();
        try
        {
            string catalogPath = Path.Combine(dir, "packages.json");
            File.WriteAllText(catalogPath, """
                {
                  "tools": {
                    "winget-z": {
                      "source": "winget", "id": "Z.Z", "architectures": ["arm64"]
                    },
                    "store": {
                      "source": "store", "id": "Store.App", "architectures": ["arm64"]
                    },
                    "amd64": {
                      "source": "winget", "id": "X.X", "architectures": ["amd64"]
                    },
                    "empty-architectures": {
                      "source": "winget", "id": "Empty.Empty", "architectures": []
                    },
                    "scoop": {
                      "source": "scoop", "id": "alpha", "scoopBucket": "extras",
                      "architectures": ["arm64"]
                    },
                    "winget-a": {
                      "source": "winget", "id": "A.A", "architectures": ["arm64"]
                    }
                  }
                }
                """);

            PackageCatalog catalog = PackageCatalog.TryLoadFromFile(catalogPath).Value;
            IReadOnlyList<PackagesProofEntry> entries = PackagesProof.BuildProveSet(catalog, "arm64");

            Assert.Equal(
                [
                    new PackagesProofEntry("scoop", "alpha", "extras"),
                    new PackagesProofEntry("winget", "A.A", null),
                    new PackagesProofEntry("winget", "Z.Z", null),
                ],
                entries);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    public static TheoryData<string> InvalidProofEntries => new()
    {
        // extra
        { """[{"source":"scoop","id":"alpha","bucket":"extras","method":"scoop-manifest-download"},{"source":"winget","id":"A.A","method":"winget-download"},{"source":"winget","id":"B.B","method":"winget-download"}]""" },
        // duplicate / missing
        { """[{"source":"scoop","id":"alpha","bucket":"extras","method":"scoop-manifest-download"},{"source":"scoop","id":"alpha","bucket":"extras","method":"scoop-manifest-download"}]""" },
        // reordered
        { """[{"source":"winget","id":"A.A","method":"winget-download"},{"source":"scoop","id":"alpha","bucket":"extras","method":"scoop-manifest-download"}]""" },
        // wrong bucket
        { """[{"source":"scoop","id":"alpha","bucket":"main","method":"scoop-manifest-download"},{"source":"winget","id":"A.A","method":"winget-download"}]""" },
        // wrong method
        { """[{"source":"scoop","id":"alpha","bucket":"extras","method":"winget-download"},{"source":"winget","id":"A.A","method":"winget-download"}]""" },
        // malformed
        { """[{},{"source":"winget","id":"A.A","method":"winget-download"}]""" },
    };

    [Theory]
    [MemberData(nameof(InvalidProofEntries))]
    public void Validate_rejects_any_non_exact_entry_sequence(string entriesJson)
    {
        string dir = NewTemp();
        try
        {
            string catalogPath = Path.Combine(dir, "packages.json");
            File.WriteAllText(catalogPath, """
                {
                  "tools": {
                    "scoop": {
                      "source": "scoop", "id": "alpha", "scoopBucket": "extras",
                      "architectures": ["arm64"]
                    },
                    "winget": {
                      "source": "winget", "id": "A.A", "architectures": ["arm64"]
                    }
                  }
                }
                """);
            PackageCatalog catalog = PackageCatalog.TryLoadFromFile(catalogPath).Value;
            IReadOnlyList<PackagesProofEntry> proveSet =
                PackagesProof.BuildProveSet(catalog, "arm64");
            string proofPath = Path.Combine(dir, "packages.proof.json");
            File.WriteAllText(proofPath, $$"""
                {
                  "schemaVersion": "winmint.packages.proof/v1",
                  "architecture": "arm64",
                  "catalogSha256": "{{PackagesProof.CatalogSha256(catalogPath)}}",
                  "proveSetSha256": "{{PackagesProof.ProveSetSha256(proveSet)}}",
                  "provenAtUtc": "2026-08-12T00:00:00Z",
                  "host": { "osArchitecture": "Arm64", "wingetVersion": "test" },
                  "entries": {{entriesJson}}
                }
                """);

            IReadOnlyList<string> errors =
                PackagesProof.Validate(proofPath, catalogPath, catalog, "arm64");

            Assert.NotEmpty(errors);
            Assert.Contains(errors, error => error.Contains("proof entr", StringComparison.Ordinal));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void Reconcile_requires_exact_successful_results_and_zero_exit()
    {
        PackagesCheckRequestFile request = Request();
        PackagesCheckOutcomeFile outcome = SuccessfulOutcome();

        Result<PackagesProofFile, Failure> ok = PackagesProof.Reconcile(request, outcome, 0);
        Assert.True(ok.IsOk);
        Assert.Equal(
            ["scoop", "winget"],
            ok.Value.Entries!.Select(entry => entry!.Source));

        (outcome.Results![0], outcome.Results[1]) = (outcome.Results[1], outcome.Results[0]);
        Assert.False(PackagesProof.Reconcile(request, outcome, 0).IsOk);

        outcome = SuccessfulOutcome();
        outcome.Results![0]!.Method = "winget-download";
        Assert.False(PackagesProof.Reconcile(request, outcome, 0).IsOk);

        outcome = SuccessfulOutcome();
        outcome.Results![0]!.Succeeded = false;
        outcome.Results[0]!.Error = "download failed";
        Assert.False(PackagesProof.Reconcile(request, outcome, 1).IsOk);

        outcome = SuccessfulOutcome();
        Assert.False(PackagesProof.Reconcile(request, outcome, 7).IsOk);
    }

    [Fact]
    public void Reconcile_surfaces_fatal_and_process_failures_before_result_symptoms()
    {
        PackagesCheckOutcomeFile outcome = SuccessfulOutcome();
        outcome.FatalError = "winget source unavailable";
        outcome.Results = [];

        Result<PackagesProofFile, Failure> fatal = PackagesProof.Reconcile(Request(), outcome, 9);
        Assert.False(fatal.IsOk);
        Assert.Contains("fatal error: winget source unavailable", fatal.Error.Message, StringComparison.Ordinal);

        outcome.FatalError = null;
        Result<PackagesProofFile, Failure> exited = PackagesProof.Reconcile(Request(), outcome, 9);
        Assert.False(exited.IsOk);
        Assert.Contains("process exited 9", exited.Error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Refresh_rejects_duplicate_catalog_install_ids_before_execution()
    {
        string dir = NewTemp();
        try
        {
            Directory.CreateDirectory(Path.Combine(dir, "config"));
            File.WriteAllText(Path.Combine(dir, "config", "packages.json"), """
                {
                  "tools": {
                    "first": {
                      "source": "winget", "id": "Contoso.Same", "architectures": ["arm64"]
                    },
                    "second": {
                      "source": "winget", "id": "Contoso.Same", "architectures": ["arm64"]
                    }
                  }
                }
                """);

            Result<PackagesProofRefreshResult, Failure> result =
                await PackagesProof.RefreshAsync(dir, TestContext.Current.CancellationToken);

            Assert.False(result.IsOk);
            Assert.Equal("packages.proof.duplicateIdentity", result.Error.Code);
            Assert.False(Directory.Exists(Path.Combine(dir, ".scratch")));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void Reconcile_rejects_duplicate_request_identities()
    {
        PackagesCheckRequestFile request = Request();
        request.Entries[1] = new PackagesCheckEntryFile
        {
            Source = "scoop",
            Id = "alpha",
            Bucket = "extras",
        };

        Result<PackagesProofFile, Failure> result =
            PackagesProof.Reconcile(request, SuccessfulOutcome(), 0);

        Assert.False(result.IsOk);
        Assert.Contains("duplicate", result.Error.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Reconcile_requires_timestamp_and_complete_native_host_diagnostics()
    {
        PackagesCheckOutcomeFile outcome = SuccessfulOutcome();
        outcome.CompletedAtUtc = null;
        Assert.False(PackagesProof.Reconcile(Request(), outcome, 0).IsOk);

        outcome = SuccessfulOutcome();
        outcome.CompletedAtUtc = default;
        Assert.False(PackagesProof.Reconcile(Request(), outcome, 0).IsOk);

        outcome = SuccessfulOutcome();
        outcome.CompletedAtUtc = new DateTimeOffset(
            2026, 8, 12, 1, 0, 0, TimeSpan.FromHours(1));
        Assert.False(PackagesProof.Reconcile(Request(), outcome, 0).IsOk);

        outcome = SuccessfulOutcome();
        outcome.Host!.ProcessArchitecture = null;
        Assert.False(PackagesProof.Reconcile(Request(), outcome, 0).IsOk);

        outcome = SuccessfulOutcome();
        outcome.Host!.ProcessorArchitecture = "AMD64";
        Assert.False(PackagesProof.Reconcile(Request(), outcome, 0).IsOk);

        outcome = SuccessfulOutcome();
        outcome.Host!.WingetVersion = "";
        Assert.False(PackagesProof.Reconcile(Request(), outcome, 0).IsOk);

        outcome = SuccessfulOutcome();
        outcome.Host = new PackagesCheckHostFile
        {
            OsArchitecture = "Arm64",
            ProcessArchitecture = "Arm64",
            ProcessorArchitecture = "ARM64",
            WingetVersion = "v1",
        };
        Assert.False(PackagesProof.Reconcile(Request(), outcome, 0).IsOk);
    }

    [Fact]
    public void Validate_requires_timestamp_and_complete_native_host_diagnostics()
    {
        string dir = NewTemp();
        try
        {
            string catalogPath = Path.Combine(dir, "packages.json");
            File.WriteAllText(catalogPath, """
                {"tools":{"a":{"source":"winget","id":"A.A","architectures":["arm64"]}}}
                """);
            PackageCatalog catalog = PackageCatalog.TryLoadFromFile(catalogPath).Value;
            string proofPath = Path.Combine(dir, "packages.proof.json");

            WriteProof(catalogPath, catalog, proofPath, "null", ValidHostJson);
            Assert.Contains(
                PackagesProof.Validate(proofPath, catalogPath, catalog, "arm64"),
                error => error.Contains("provenAtUtc", StringComparison.Ordinal));

            WriteProof(catalogPath, catalog, proofPath, "\"not-a-time\"", ValidHostJson);
            Assert.Contains(
                PackagesProof.Validate(proofPath, catalogPath, catalog, "arm64"),
                error => error.Contains("parse failed", StringComparison.Ordinal));

            WriteProof(
                catalogPath,
                catalog,
                proofPath,
                "\"2026-08-12T00:00:00Z\"",
                """{"osArchitecture":"Arm64","processArchitecture":"X64","processorArchitecture":"ARM64","processorArchitectureW6432":null,"wingetVersion":"v1"}""");
            Assert.Contains(
                PackagesProof.Validate(proofPath, catalogPath, catalog, "arm64"),
                error => error.Contains("OS and process", StringComparison.Ordinal));

            WriteProof(
                catalogPath,
                catalog,
                proofPath,
                "\"2026-08-12T00:00:00Z\"",
                """{"osArchitecture":"Arm64","processArchitecture":"Arm64","processorArchitecture":"ARM64","processorArchitectureW6432":null,"wingetVersion":""}""");
            Assert.Contains(
                PackagesProof.Validate(proofPath, catalogPath, catalog, "arm64"),
                error => error.Contains("wingetVersion", StringComparison.Ordinal));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void Scratch_cleanup_failure_preserves_old_proof_and_reports_failure()
    {
        string dir = NewTemp();
        try
        {
            string proofPath = Path.Combine(dir, "packages.proof.json");
            File.WriteAllText(proofPath, "old proof");
            string runDirectory = Directory.CreateDirectory(Path.Combine(dir, "run")).FullName;
            string diagnosticPath = Path.Combine(runDirectory, "request.json");
            File.WriteAllText(diagnosticPath, "diagnostic");

            Result<PackagesProofFile, Failure> result;
            using (FileStream held = new(
                diagnosticPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read))
            {
                result = PackagesProof.ReplaceProofAfterScratchCleanup(
                    proofPath,
                    runDirectory,
                    ValidProofFile());
            }

            Assert.False(result.IsOk);
            Assert.Equal("packages.proof.scratchCleanupFailed", result.Error.Code);
            Assert.Equal("old proof", File.ReadAllText(proofPath));
            Assert.True(Directory.Exists(runDirectory));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void PackagesProof_public_surface_is_refresh_and_validate_only()
    {
        string[] methods = [.. typeof(PackagesProof)
            .GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.DeclaredOnly)
            .Select(method => method.Name)
            .Order(StringComparer.Ordinal)];

        Assert.Equal(["RefreshAsync", "Validate"], methods);
        Assert.False(typeof(PackagesProofEntry).IsPublic);
    }

    private static PackagesCheckRequestFile Request() => new()
    {
        SchemaVersion = PackagesProof.RequestSchemaVersion,
        Architecture = "arm64",
        CatalogSha256 = new string('a', 64),
        Entries =
        [
            new PackagesCheckEntryFile { Source = "scoop", Id = "alpha", Bucket = "extras" },
            new PackagesCheckEntryFile { Source = "winget", Id = "A.A" },
        ],
    };

    private static PackagesCheckOutcomeFile SuccessfulOutcome() => new()
    {
        SchemaVersion = PackagesProof.OutcomeSchemaVersion,
        Architecture = "arm64",
        CatalogSha256 = new string('a', 64),
        CompletedAtUtc = new DateTimeOffset(2026, 8, 12, 0, 0, 0, TimeSpan.Zero),
        Host = new PackagesCheckHostFile
        {
            OsArchitecture = "Arm64",
            ProcessArchitecture = "Arm64",
            ProcessorArchitecture = "ARM64",
            ProcessorArchitectureW6432 = null,
            WingetVersion = "v1",
        },
        Results =
        [
            new PackagesCheckResultFile
            {
                Source = "scoop",
                Id = "alpha",
                Bucket = "extras",
                Succeeded = true,
                Method = "scoop-manifest-download",
            },
            new PackagesCheckResultFile
            {
                Source = "winget",
                Id = "A.A",
                Succeeded = true,
                Method = "winget-download",
            },
        ],
    };

    private const string ValidHostJson =
        """{"osArchitecture":"Arm64","processArchitecture":"Arm64","processorArchitecture":"ARM64","processorArchitectureW6432":null,"wingetVersion":"v1"}""";

    private static void WriteProof(
        string catalogPath,
        PackageCatalog catalog,
        string proofPath,
        string provenAtJson,
        string hostJson)
    {
        IReadOnlyList<PackagesProofEntry> proveSet =
            PackagesProof.BuildProveSet(catalog, "arm64");
        File.WriteAllText(proofPath, $$"""
            {
              "schemaVersion": "winmint.packages.proof/v1",
              "architecture": "arm64",
              "catalogSha256": "{{PackagesProof.CatalogSha256(catalogPath)}}",
              "proveSetSha256": "{{PackagesProof.ProveSetSha256(proveSet)}}",
              "provenAtUtc": {{provenAtJson}},
              "host": {{hostJson}},
              "entries": [
                {"source":"winget","id":"A.A","method":"winget-download"}
              ]
            }
            """);
    }

    private static PackagesProofFile ValidProofFile() => new()
    {
        SchemaVersion = PackagesProof.SchemaVersion,
        Architecture = "arm64",
        CatalogSha256 = new string('a', 64),
        ProveSetSha256 = new string('b', 64),
        ProvenAtUtc = new DateTimeOffset(2026, 8, 12, 0, 0, 0, TimeSpan.Zero),
        Host = new PackagesProofHostFile
        {
            OsArchitecture = "Arm64",
            ProcessArchitecture = "Arm64",
            ProcessorArchitecture = "ARM64",
            ProcessorArchitectureW6432 = null,
            WingetVersion = "v1",
        },
        Entries = [],
    };

    private static string NewTemp() =>
        Directory.CreateDirectory(
            Path.Combine(Path.GetTempPath(), "winmint-proof-" + Guid.NewGuid().ToString("N")))
            .FullName;

}
