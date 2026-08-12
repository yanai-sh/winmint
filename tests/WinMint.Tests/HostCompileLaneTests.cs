using System.Text.Json;
using WinMint.Contracts;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class HostCompileLaneTests
{
    [Fact]
    public async Task Apply_Release_defaults_package_strict_false()
    {
        await AssertPackageStrictAsync(ImageQualityLane.Release, packageStrict: false, expected: false);
    }

    [Fact]
    public async Task Apply_explicit_package_strict_true()
    {
        await AssertPackageStrictAsync(ImageQualityLane.Test, packageStrict: true, expected: true);
    }

    private static async Task AssertPackageStrictAsync(
        ImageQualityLane lane,
        bool packageStrict,
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

            Result<HostCompileResult, Failure> result = await HostCompile.ApplyAsync(
                new HostCompileRequest(
                    profile,
                    iso,
                    ImageQuality: lane,
                    WorkDirectory: work,
                    PackageStrict: packageStrict),
                new ImageServicingTestFakes.RecordingElevatedPlanRunner(),
                TestContext.Current.CancellationToken);

            Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
            Assert.True(result.Value.Succeeded);
            Assert.Equal(expected, result.Value.Plan.PackageStrict);
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

    private static Profile Profile() =>
        new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget(true, "en-GB", 242, "GMT Standard Time", true)),
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
}
