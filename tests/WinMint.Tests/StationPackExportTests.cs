using System.Text.Json;

using WinMint.Contracts;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class StationPackExportTests
{
    [Fact]
    public void ExportStationPack_writes_profile_and_export_plan_siblings()
    {
        Profile profile = Lab() with { WingetPackages = [ProductPosture.BraveWingetId] };
        Result<HostPlan, HostComposeError> host = HostCompile.PlanDocument(profile);
        Assert.True(host.IsOk, host.IsOk ? null : host.Error.Message);
        string dest = Path.Combine(Path.GetTempPath(), "winmint-pack-" + Guid.NewGuid().ToString("N"));
        try
        {
            Result<StationPackResult, Failure> packed =
                HostCompile.ExportStationPack(host.Value, profile, dest);
            Assert.True(packed.IsOk, packed.IsOk ? null : $"{packed.Error.Code}: {packed.Error.Message}");
            Assert.Equal(Path.GetFullPath(dest), packed.Value.Directory);
            Assert.True(File.Exists(packed.Value.ProfilePath));
            Assert.Equal(
                Path.Combine(Path.GetFullPath(dest), "winmint.profile.json"),
                packed.Value.ProfilePath,
                ignoreCase: true);

            Assert.True(File.Exists(Path.Combine(dest, "jobs.json")));
            Assert.True(File.Exists(Path.Combine(dest, "stages.json")));
            Assert.True(File.Exists(Path.Combine(dest, "manifest.json")));
            Assert.True(File.Exists(Path.Combine(dest, "unattend.xml")));
            Assert.True(File.Exists(Path.Combine(dest, "winget-import.json")));
            Assert.True(File.Exists(Path.Combine(dest, ServicingWorkspace.WingetConfigurationFileName)));

            string json = File.ReadAllText(packed.Value.ProfilePath);
            using JsonDocument doc = JsonDocument.Parse(json);
            Assert.Equal(
                "winmint.profile/v1",
                doc.RootElement.GetProperty("schemaVersion").GetString());
            Assert.DoesNotContain("environment", json, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            if (Directory.Exists(dest))
            {
                Directory.Delete(dest, recursive: true);
            }
        }
    }

    [Fact]
    public void ExportStationPack_writes_password_sidecar_like_emit_defaults()
    {
        Profile profile = Lab();
        Result<HostPlan, HostComposeError> host = HostCompile.PlanDocument(profile);
        Assert.True(host.IsOk);
        string dest = Path.Combine(Path.GetTempPath(), "winmint-pack-pw-" + Guid.NewGuid().ToString("N"));
        try
        {
            Result<StationPackResult, Failure> packed =
                HostCompile.ExportStationPack(host.Value, profile, dest);
            Assert.True(packed.IsOk, packed.IsOk ? null : packed.Error.Message);

            string sidecar = Path.Combine(dest, "account.password");
            Assert.True(File.Exists(sidecar));
            Assert.Equal("lab-only", File.ReadAllText(sidecar).Trim());

            string json = File.ReadAllText(packed.Value.ProfilePath);
            Assert.Contains("\"passwordPath\": \"account.password\"", json, StringComparison.Ordinal);
            Assert.DoesNotContain("lab-only", json, StringComparison.Ordinal);
        }
        finally
        {
            if (Directory.Exists(dest))
            {
                Directory.Delete(dest, recursive: true);
            }
        }
    }

    [Fact]
    public async Task ComposeFileAsync_from_pack_profile_ignores_sibling_plan_files()
    {
        Profile profile = Lab() with { RemoveProvisionedAppx = ["Microsoft.GetHelp"] };
        Result<HostPlan, HostComposeError> host = HostCompile.PlanDocument(profile);
        Assert.True(host.IsOk);
        string dest = Path.Combine(Path.GetTempPath(), "winmint-pack-apply-" + Guid.NewGuid().ToString("N"));
        string iso = Path.Combine(dest, "source.iso");
        try
        {
            Assert.True(HostCompile.ExportStationPack(host.Value, profile, dest).IsOk);
            File.WriteAllText(iso, "iso-stub");
            // Corrupt plan siblings — Apply intent must remain the Profile only.
            File.WriteAllText(Path.Combine(dest, "stages.json"), "{ not-a-plan");
            File.WriteAllText(Path.Combine(dest, "jobs.json"), "[]");
            File.Delete(Path.Combine(dest, "manifest.json"));

            Result<HostComposition, HostComposeError> composed = await HostCompile.ComposeFileAsync(
                Path.Combine(dest, "winmint.profile.json"),
                new HostComposeOptions(
                    iso,
                    ImageQualityLane.Test,
                    Path.Combine(dest, "work"),
                    WimIndex: 1),
                new PackProbe(),
                TestContext.Current.CancellationToken);

            Assert.True(composed.IsOk, composed.IsOk ? null : composed.Error.Message);
            Assert.Contains(
                "Microsoft.GetHelp",
                composed.Value.Review.RemoveProvisionedAppx,
                StringComparer.OrdinalIgnoreCase);
        }
        finally
        {
            if (Directory.Exists(dest))
            {
                Directory.Delete(dest, recursive: true);
            }
        }
    }

    private static Profile Lab() =>
        new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            []);

    private sealed class PackProbe : ISourceMediaProbe
    {
        public Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> ListIndexesAsync(
            string sourceIsoPath,
            CancellationToken cancellationToken = default)
        {
            WimIndexInfo row = new(1, "Windows 11 Pro", "ARM64", "Professional", "10.0.26100.1", "26100");
            return TestIso.List(row);
        }

        public Task<Result<SourceMediaReview, Failure>> ProbeAsync(
            string sourceIsoPath,
            int wimIndex,
            CancellationToken cancellationToken = default)
        {
            SourceIsoIdentity id = TestIso.Identity(sourceIsoPath);
            WimIndexInfo row = new(wimIndex, "Windows 11 Pro", "ARM64", "Professional", "10.0.26100.1", "26100");
            return Task.FromResult(Result.Ok<SourceMediaReview, Failure>(
                new(
                    Path.GetFullPath(sourceIsoPath),
                    id,
                    Array.AsReadOnly([row]),
                    new(wimIndex, row.Name, row.Architecture, row.Edition, row.Version, row.Build))));
        }
    }
}
