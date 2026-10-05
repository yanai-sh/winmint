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
    public void ExportStationPack_copies_passwordPath_sidecar_from_source_directory()
    {
        string source = Path.Combine(Path.GetTempPath(), "winmint-pack-src-" + Guid.NewGuid().ToString("N"));
        string dest = Path.Combine(Path.GetTempPath(), "winmint-pack-dst-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(source);
        try
        {
            File.WriteAllText(Path.Combine(source, "password.txt"), "sidecar-secret");
            // Plan needs a materialised secret; pack Apply profile is passwordPath-only (Save Profile shape).
            Result<HostPlan, HostComposeError> host = HostCompile.PlanDocument(Lab());
            Assert.True(host.IsOk, host.IsOk ? null : host.Error.Message);
            Profile packProfile = Lab() with
            {
                Account = new AccountProfile(
                    "winmint",
                    Password: null,
                    RequireWifiDuringOobe: false,
                    PasswordPath: "password.txt"),
            };

            Result<StationPackResult, Failure> packed =
                HostCompile.ExportStationPack(host.Value, packProfile, dest, source);
            Assert.True(packed.IsOk, packed.IsOk ? null : packed.Error.Message);
            Assert.Equal("sidecar-secret", File.ReadAllText(Path.Combine(dest, "password.txt")).Trim());
            string json = File.ReadAllText(packed.Value.ProfilePath);
            Assert.Contains("\"passwordPath\": \"password.txt\"", json, StringComparison.Ordinal);
            Assert.DoesNotContain("sidecar-secret", json, StringComparison.Ordinal);
        }
        finally
        {
            if (Directory.Exists(source))
            {
                Directory.Delete(source, recursive: true);
            }

            if (Directory.Exists(dest))
            {
                Directory.Delete(dest, recursive: true);
            }
        }
    }

    [Fact]
    public async Task ExportStationPack_from_composition_copies_sidecar_via_source_profile_directory()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-pack-comp-" + Guid.NewGuid().ToString("N"));
        string dest = Path.Combine(root, "pack");
        Directory.CreateDirectory(root);
        try
        {
            File.WriteAllText(Path.Combine(root, "password.txt"), "from-source");
            string profilePath = Path.Combine(root, "loaded.profile.json");
            File.WriteAllText(profilePath, """
                {
                  "schemaVersion": "winmint.profile/v1",
                  "account": {
                    "mode": "localAutoLogon",
                    "username": "winmint",
                    "passwordPath": "password.txt",
                    "requireWifiDuringOobe": false
                  },
                  "dma": {
                    "enabled": true,
                    "settle": {
                      "locale": "en-GB",
                      "geoId": 242,
                      "timeZoneId": "GMT Standard Time",
                      "locationServicesEnabled": true
                    }
                  }
                }
                """);
            string iso = Path.Combine(root, "source.iso");
            File.WriteAllText(iso, "iso-stub");

            Result<HostComposition, HostComposeError> composed = await HostCompile.ComposeFileAsync(
                profilePath,
                new HostComposeOptions(iso, ImageQualityLane.Test, Path.Combine(root, "work"), WimIndex: 1),
                new PackProbe(),
                TestContext.Current.CancellationToken);
            Assert.True(composed.IsOk, composed.IsOk ? null : composed.Error.Message);

            Result<StationPackResult, Failure> packed =
                HostCompile.ExportStationPack(composed.Value, dest);
            Assert.True(packed.IsOk, packed.IsOk ? null : packed.Error.Message);
            Assert.Equal("from-source", File.ReadAllText(Path.Combine(dest, "password.txt")).Trim());
            Assert.Contains(
                "\"passwordPath\": \"password.txt\"",
                File.ReadAllText(packed.Value.ProfilePath),
                StringComparison.Ordinal);
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    [Fact]
    public void ExportStationPack_passwordPath_without_source_fails_closed()
    {
        Result<HostPlan, HostComposeError> host = HostCompile.PlanDocument(Lab());
        Assert.True(host.IsOk, host.IsOk ? null : host.Error.Message);
        Profile packProfile = Lab() with
        {
            Account = new AccountProfile(
                "winmint",
                Password: null,
                RequireWifiDuringOobe: false,
                PasswordPath: "missing.password"),
        };
        string dest = Path.Combine(Path.GetTempPath(), "winmint-pack-miss-" + Guid.NewGuid().ToString("N"));
        try
        {
            Result<StationPackResult, Failure> packed =
                HostCompile.ExportStationPack(host.Value, packProfile, dest);
            Assert.False(packed.IsOk);
            Assert.Equal("stationPack.password.missing", packed.Error.Code);
            Assert.False(File.Exists(Path.Combine(dest, "jobs.json")));
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
