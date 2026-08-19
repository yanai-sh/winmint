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
}
