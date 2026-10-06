using System.Text.Json;

using WinMint.Contracts;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class HostCompileLaneTests
{
    [Theory]
    [InlineData(ImageQualityLane.Test, PackageStrictOverride.FromLane, false)]
    [InlineData(ImageQualityLane.Release, PackageStrictOverride.FromLane, true)]
    [InlineData(ImageQualityLane.Test, PackageStrictOverride.Force, true)]
    [InlineData(ImageQualityLane.Release, PackageStrictOverride.Force, true)]
    [InlineData(ImageQualityLane.Test, PackageStrictOverride.Suppress, false)]
    [InlineData(ImageQualityLane.Release, PackageStrictOverride.Suppress, false)]
    public async Task Apply_resolves_package_strict_once_for_the_staged_bundle(
        ImageQualityLane lane,
        PackageStrictOverride packageStrict,
        bool expected)
    {
        await AssertPackageStrictAsync(lane, packageStrict, expected);
    }

    private static async Task AssertPackageStrictAsync(
        ImageQualityLane lane,
        PackageStrictOverride packageStrict,
        bool expected)
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-host-lane-" + Guid.NewGuid().ToString("N"));
        string profile = Path.Combine(root, "profile.json");
        string iso = Path.Combine(root, "source.iso");
        string work = Path.Combine(root, "work");
        Directory.CreateDirectory(root);
        try
        {
            File.WriteAllBytes(profile, BuildPlan.SerializeProfile(Profile()));
            File.WriteAllText(iso, "iso-stub");

            Result<HostComposition, HostComposeError> composed = await HostCompile.ComposeFileAsync(
                profile,
                new HostComposeOptions(
                    iso,
                    lane,
                    work,
                    WimIndex: 1,
                    PackageStrict: packageStrict),
                new FixedProbe(),
                cancellationToken: TestContext.Current.CancellationToken);
            Assert.True(composed.IsOk, composed.IsOk ? null : $"{composed.Error.Code}: {composed.Error.Message}");
            Assert.Equal(expected, composed.Value.Review.PackageStrict);
            Assert.Equal(
                lane == ImageQualityLane.Release && expected,
                composed.Value.Review.IsGateB);
            Result<ImageEvidence, Failure> result = await HostCompile.ApplyAsync(
                composed.Value,
                new ImageServicingTestFakes.RecordingElevatedPlanRunner(),
                TestContext.Current.CancellationToken);
            Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
            using JsonDocument bundle = JsonDocument.Parse(
                File.ReadAllBytes(Path.Combine(work, "payload", "bundle.json")));
            Assert.Equal(expected, bundle.RootElement.GetProperty("packageStrict").GetBoolean());
            if (bundle.RootElement.GetProperty("dmaEnabled").GetBoolean())
            {
                JsonElement settle = bundle.RootElement.GetProperty("settle");
                Assert.False(string.IsNullOrWhiteSpace(settle.GetProperty("locale").GetString()));
                Assert.False(string.IsNullOrWhiteSpace(settle.GetProperty("timeZoneId").GetString()));
                Assert.True(settle.GetProperty("geoId").TryGetInt32(out _));
                Assert.True(settle.TryGetProperty("locationServicesEnabled", out JsonElement loc));
                Assert.True(loc.ValueKind is JsonValueKind.True or JsonValueKind.False);
            }

            string payload = Path.Combine(work, ServicingWorkspace.PayloadDirectoryName);
            string defaultUserJson = File.ReadAllText(
                Path.Combine(payload, ServicingWorkspace.DefaultUserFileName));
            Assert.NotEqual("[]", defaultUserJson.Trim());
            Assert.Contains("AppsUseLightTheme", defaultUserJson, StringComparison.Ordinal);
            string policiesJson = File.ReadAllText(
                Path.Combine(payload, ServicingWorkspace.PoliciesFileName));
            Assert.NotEqual("[]", policiesJson.Trim());
            Assert.Contains("HideFirstRunExperience", policiesJson, StringComparison.Ordinal);
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    [Theory]
    [InlineData(ImageQualityLane.Test, PackageStrictOverride.FromLane, false)]
    [InlineData(ImageQualityLane.Release, PackageStrictOverride.FromLane, true)]
    [InlineData(ImageQualityLane.Release, PackageStrictOverride.Suppress, false)]
    public void PlanDocument_resolves_package_strict_and_gate_b(
        ImageQualityLane lane,
        PackageStrictOverride packageStrict,
        bool expectedStrict)
    {
        Result<HostPlan, HostComposeError> planned = HostCompile.PlanDocument(
            Profile(),
            new HostComposeOptions(ImageQuality: lane, PackageStrict: packageStrict));
        Assert.True(planned.IsOk, planned.IsOk ? null : planned.Error.Message);
        Assert.Equal(expectedStrict, planned.Value.Review.PackageStrict);
        Assert.Equal(lane == ImageQualityLane.Release && expectedStrict, planned.Value.Review.IsGateB);
    }

    [Fact]
    public void PlanDocument_keeps_default_user_rows()
    {
        Result<HostPlan, HostComposeError> planned = HostCompile.PlanDocument(Profile());
        Assert.True(planned.IsOk, planned.IsOk ? null : planned.Error.Message);
        Assert.NotEmpty(planned.Value.Artifacts.OfflineDefaultUser);
        Assert.Contains(
            planned.Value.Artifacts.OfflineDefaultUser,
            static row => row.Name == "AppsUseLightTheme");
    }

    [Fact]
    public void PlanDocument_preserves_plan_artifacts()
    {
        Profile profile = Sl7DriversProfile() with { WingetPackages = [ProductPosture.BraveWingetId] };
        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        Result<HostPlan, HostComposeError> host = HostCompile.PlanDocument(profile);
        Assert.True(host.IsOk, host.IsOk ? null : host.Error.Message);

        BuildArtifacts raw = planned.Value;
        BuildArtifacts snap = host.Value.Artifacts;
        Assert.Equal(raw.Unattend.Xml, snap.Unattend.Xml);
        Assert.Equal(raw.Manifest, snap.Manifest);
        Assert.Equal(raw.Account.Username, snap.Account.Username);
        Assert.Equal(raw.Dma, snap.Dma);
        Assert.Equal(raw.Stages, snap.Stages);
        Assert.Equal(raw.OfflineDefaultUser, snap.OfflineDefaultUser);
        Assert.Equal(raw.OfflinePolicies, snap.OfflinePolicies);
        Assert.Equal(raw.Drivers, snap.Drivers);
        Assert.Equal(raw.WingetImportJson, snap.WingetImportJson);
        Assert.Equal(raw.PackageStrict, snap.PackageStrict);
        Assert.Equal(raw.BraveSelected, snap.BraveSelected);
        Assert.Equal(raw.RemoveProvisionedAppx, snap.RemoveProvisionedAppx);
        Assert.Equal(raw.RemoveCapabilities, snap.RemoveCapabilities);
        Assert.Equal(raw.DisableOptionalFeatures, snap.DisableOptionalFeatures);
        Assert.Equal(raw.EffectivePackages, snap.EffectivePackages);
        Assert.Equal(raw.Jobs.SchemaVersion, snap.Jobs.SchemaVersion);
        Assert.Equal(raw.Jobs.Jobs.Count, snap.Jobs.Jobs.Count);
        for (int i = 0; i < raw.Jobs.Jobs.Count; i++)
        {
            ProvisionJob a = raw.Jobs.Jobs[i];
            ProvisionJob b = snap.Jobs.Jobs[i];
            Assert.Equal(a.Id, b.Id);
            Assert.Equal(a.Kind, b.Kind);
            Assert.Equal(a.PackageId, b.PackageId);
            Assert.Equal(a.NeedsReboot, b.NeedsReboot);
            Assert.Equal(a.DohPrimary, b.DohPrimary);
            Assert.Equal(a.ScoopBuckets ?? [], b.ScoopBuckets ?? []);
        }
        Assert.NotNull(snap.Drivers);
        Assert.NotEmpty(snap.OfflineDefaultUser);
        Assert.NotEmpty(snap.OfflinePolicies);
        Assert.NotNull(snap.WingetImportJson);
        Assert.True(snap.WingetImportJson!.Length > 2);

        HostReview review = host.Value.Review;
        Assert.Equal(snap.Stages, review.Stages);
        Assert.Equal(snap.RemoveProvisionedAppx, review.RemoveProvisionedAppx);
        Assert.Equal(snap.EffectivePackages, review.EffectivePackages);
        Assert.Equal(snap.PackageStrict, review.PackageStrict);
        Assert.Equal(snap.BraveSelected, review.BraveSelected);
        Assert.Equal(snap.Manifest.ImageQuality, review.ImageQuality);
        Assert.Equal(snap.Manifest.RequiresNetwork, review.RequiresNetwork);
        Assert.Equal(snap.Jobs.Jobs.Count, review.Jobs.Count);
        Assert.Equal(
            snap.Jobs.Jobs.Select(static j => j.Id),
            review.Jobs.Select(static j => j.Id));
    }

    [Theory]
    [InlineData(typeof(HostReview))]
    [InlineData(typeof(BuildArtifacts))]
    [InlineData(typeof(JobsArtifact))]
    public void Snapshot_records_have_no_optional_constructor_parameters(Type type)
    {
        Assert.DoesNotContain(
            type.GetConstructors().SelectMany(static ctor => ctor.GetParameters()),
            static parameter => parameter.HasDefaultValue);
    }

    [Fact]
    public void ExportPlan_writes_payload_facts()
    {
        Profile profile = Sl7DriversProfile() with { WingetPackages = [ProductPosture.BraveWingetId] };
        Result<HostPlan, HostComposeError> host = HostCompile.PlanDocument(profile);
        Assert.True(host.IsOk, host.IsOk ? null : host.Error.Message);
        string dest = Path.Combine(Path.GetTempPath(), "winmint-export-" + Guid.NewGuid().ToString("N"));
        try
        {
            Result<Unit, Failure> exported = HostCompile.ExportPlan(host.Value, dest);
            Assert.True(exported.IsOk, exported.IsOk ? null : $"{exported.Error.Code}: {exported.Error.Message}");
            string defaultUserJson = File.ReadAllText(Path.Combine(dest, ServicingWorkspace.DefaultUserFileName));
            Assert.NotEqual("[]", defaultUserJson.Trim());
            Assert.Contains("AppsUseLightTheme", defaultUserJson, StringComparison.Ordinal);
            string policiesJson = File.ReadAllText(Path.Combine(dest, ServicingWorkspace.PoliciesFileName));
            Assert.NotEqual("[]", policiesJson.Trim());
            Assert.Contains("HideFirstRunExperience", policiesJson, StringComparison.Ordinal);
            Assert.True(File.Exists(Path.Combine(dest, "winget-import.json")));
            Assert.True(new FileInfo(Path.Combine(dest, "winget-import.json")).Length > 2);
            string configurationYaml = File.ReadAllText(
                Path.Combine(dest, ServicingWorkspace.WingetConfigurationFileName));
            Assert.Contains("Microsoft.WinGet.DSC/WinGetPackage", configurationYaml, StringComparison.Ordinal);
            Assert.Contains(ProductPosture.BraveWingetId, configurationYaml, StringComparison.Ordinal);
            Assert.Contains(
                "surface-laptop-7",
                File.ReadAllText(Path.Combine(dest, "stages.json")),
                StringComparison.Ordinal);
            Assert.True(File.Exists(Path.Combine(dest, "jobs.json")));
            Assert.True(File.Exists(Path.Combine(dest, "unattend.xml")));
            Assert.True(File.Exists(Path.Combine(dest, "manifest.json")));
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
    public async Task Compose_sl7_drivers_uses_version_family_not_servicepack_ubr()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-host-ubr-" + Guid.NewGuid().ToString("N"));
        string profile = Path.Combine(root, "profile.json");
        string iso = Path.Combine(root, "source.iso");
        Directory.CreateDirectory(root);
        try
        {
            File.WriteAllBytes(profile, BuildPlan.SerializeProfile(Sl7DriversProfile()));
            File.WriteAllText(iso, "iso-stub");
            Result<HostComposition, HostComposeError> composed = await HostCompile.ComposeFileAsync(
                profile,
                new HostComposeOptions(iso, ImageQualityLane.Test, Path.Combine(root, "work"), WimIndex: 1),
                new UbrProbe(),
                cancellationToken: TestContext.Current.CancellationToken);
            Assert.True(composed.IsOk, composed.IsOk ? null : $"{composed.Error.Code}: {composed.Error.Message}");
            Assert.Contains(ServicingOpcode.InjectDrivers, composed.Value.Artifacts.Stages);
            Assert.NotNull(composed.Value.Artifacts.Drivers);
            Assert.Equal("surface-laptop-7", composed.Value.Artifacts.Drivers.DeviceId);
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    private static Profile Profile() =>
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

    private static Profile Sl7DriversProfile() =>
        Profile() with
        {
            Drivers = new DriversProfile(SurfaceDriverCatalog.SourceSurfaceCatalog, "surface-laptop-7"),
        };

    private sealed class FixedProbe : ISourceMediaProbe
    {
        public Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> ListIndexesAsync(
            string sourceIsoPath,
            CancellationToken cancellationToken = default)
        {
            WimIndexInfo row = new(ImageServicing.DefaultProWimIndex, "Windows 11 Home", "ARM64", "Core", null, "26100");
            return TestIso.List(row);
        }

        public Task<Result<SourceMediaReview, Failure>> ProbeAsync(
            string sourceIsoPath,
            int wimIndex,
            CancellationToken cancellationToken = default)
        {
            WimIndexInfo row = new(wimIndex, "Windows 11 Home", "ARM64", "Core", null, "26100");
            return Task.FromResult(Result.Ok<SourceMediaReview, Failure>(
                new SourceMediaReview(
                    Path.GetFullPath(sourceIsoPath),
                    TestIso.Identity(sourceIsoPath),
                    Array.AsReadOnly([row]),
                    new SelectedWim(wimIndex, row.Name, row.Architecture, row.Edition, row.Version, row.Build))));
        }
    }

    /// <summary>Retail 25H2 after quality: Version family 26100, ServicePack Build is UBR 8037.</summary>
    private sealed class UbrProbe : ISourceMediaProbe
    {
        public Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> ListIndexesAsync(
            string sourceIsoPath,
            CancellationToken cancellationToken = default)
        {
            WimIndexInfo row = new(1, "Windows 11 Pro", "ARM64", "Professional", "10.0.26100.1", "8037");
            return TestIso.List(row);
        }

        public Task<Result<SourceMediaReview, Failure>> ProbeAsync(
            string sourceIsoPath,
            int wimIndex,
            CancellationToken cancellationToken = default)
        {
            WimIndexInfo row = new(wimIndex, "Windows 11 Pro", "ARM64", "Professional", "10.0.26100.1", "8037");
            return Task.FromResult(Result.Ok<SourceMediaReview, Failure>(
                new SourceMediaReview(
                    Path.GetFullPath(sourceIsoPath),
                    TestIso.Identity(sourceIsoPath),
                    Array.AsReadOnly([row]),
                    new SelectedWim(wimIndex, row.Name, row.Architecture, row.Edition, row.Version, row.Build))));
        }
    }
}
