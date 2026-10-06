using System.Text.Json;

using WinMint.Contracts;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class ExpectedEvidenceWslWireTests
{
    [Fact]
    public async Task Apply_expected_evidence_lists_wsl_kinds_and_store_install_ids()
    {
        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile("""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": { "mode": "localAutoLogon", "username": "winmint", "password": "lab-only" },
              "dma": {
                "enabled": true,
                "settle": {
                  "locale": "en-GB",
                  "geoId": 242,
                  "timeZoneId": "GMT Standard Time",
                  "locationServicesEnabled": true
                }
              },
              "packages": { "wsl": ["FedoraLinux"] }
            }
            """u8.ToArray());
        Assert.True(parsed.IsOk);
        Result<HostPlan, HostComposeError> host = HostCompile.PlanDocument(parsed.Value);
        Assert.True(host.IsOk, host.IsOk ? null : host.Error.Message);

        string work = Path.Combine(Path.GetTempPath(), "winmint-wsl-evidence-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.WriteAllText(Path.Combine(work, "source.iso"), "iso-stub");
            Result<ImageEvidence, Failure> result = await ImageServicing.ApplyAsync(
                host.Value.Artifacts,
                new ServicingRun(
                    Path.Combine(work, "source.iso"),
                    work,
                    Path.Combine(work, "out.iso")),
                new ImageServicingTestFakes.RecordingElevatedPlanRunner(),
                TestContext.Current.CancellationToken);
            Assert.True(result.IsOk, result.IsOk ? null : result.Error.Message);

            using JsonDocument doc = JsonDocument.Parse(
                File.ReadAllBytes(Path.Combine(work, "expected-evidence.json")));
            HashSet<string> kinds = doc.RootElement.GetProperty("requiredJobKinds")
                .EnumerateArray()
                .Select(static e => e.GetString()!)
                .ToHashSet(StringComparer.Ordinal);
            Assert.Contains(ProvisionJobKindWire.WslPlatform, kinds);
            Assert.Contains(ProvisionJobKindWire.Wsl, kinds);

            HashSet<string> wslIds = doc.RootElement.GetProperty("requiredWslPackageIds")
                .EnumerateArray()
                .Select(static e => e.GetString()!)
                .ToHashSet(StringComparer.Ordinal);
            Assert.Contains("FedoraLinux-44", wslIds);
            Assert.True(doc.RootElement.GetProperty("packageWireHonest").GetBoolean());
            Assert.Equal(host.Value.Artifacts.PackageWireHonest,
                doc.RootElement.GetProperty("packageWireHonest").GetBoolean());
        }
        finally
        {
            try
            {
                Directory.Delete(work, recursive: true);
            }
            catch
            {
                // ponytail: temp cleanup
            }
        }
    }

    [Fact]
    public void BuildProveSet_includes_store_wsl_install_ids_for_arm64()
    {
        IReadOnlyList<PackagesProofEntry> set = PackagesProof.BuildProveSet(PackageCatalog.Default, "arm64");
        Assert.Contains(set, e => e.Source == "wsl" && e.Id == "FedoraLinux-44");
        Assert.Contains(set, e => e.Source == "wsl" && e.Id == "Ubuntu");
        Assert.DoesNotContain(set, e => e.Source == "wsl" && e.Id == "NixOS");
    }

    [Fact]
    public void Validate_fails_when_proof_omits_catalog_store_wsl_install_id()
    {
        string root = TestRepo.Root;
        string catalogPath = Path.Combine(root, "config", "packages.json");
        PackageCatalog catalog = PackageCatalog.TryLoadFromFile(catalogPath).Value;
        IReadOnlyList<PackagesProofEntry> proveSet = PackagesProof.BuildProveSet(catalog, "arm64");
        Assert.Contains(proveSet, e => e.Source == "wsl");

        string dir = Path.Combine(Path.GetTempPath(), "winmint-proof-wsl-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string proofPath = Path.Combine(dir, "packages.proof.json");
            IEnumerable<string> entryLines = proveSet
                .Where(e => e.Source is not "wsl")
                .Select(e =>
                {
                    string bucket = e.ScoopBucket is null
                        ? "null"
                        : $"\"{e.ScoopBucket}\"";
                    return $$"""{"source":"{{e.Source}}","id":"{{e.Id}}","method":"{{PackagesProof.ExpectedMethod(e.Source)}}","bucket":{{bucket}}}""";
                });
            File.WriteAllText(
                proofPath,
                $$"""
                {
                  "schemaVersion": "winmint.packages.proof/v1",
                  "architecture": "arm64",
                  "catalogSha256": "{{PackagesProof.CatalogSha256(catalogPath)}}",
                  "proveSetSha256": "{{PackagesProof.ProveSetSha256(proveSet)}}",
                  "provenAtUtc": "2026-10-06T00:00:00Z",
                  "host": {
                    "osArchitecture": "Arm64",
                    "processArchitecture": "Arm64",
                    "processorArchitecture": "ARM64",
                    "processorArchitectureW6432": null,
                    "wingetVersion": "test"
                  },
                  "entries": [
                {{string.Join(",\n", entryLines)}}
                  ]
                }
                """);

            IReadOnlyList<string> errors = PackagesProof.Validate(proofPath, catalogPath, catalog, "arm64");
            Assert.NotEmpty(errors);
            Assert.True(
                errors.Any(static e =>
                    e.Contains("proveSetSha256", StringComparison.Ordinal)
                    || e.Contains("proof entries count", StringComparison.Ordinal)),
                string.Join(Environment.NewLine, errors));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }
}
