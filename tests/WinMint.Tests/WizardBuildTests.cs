using WinMint.Contracts;
using WinMint.Orchestrator;
using WinMint.Wizard;

namespace WinMint.Tests;

public class WizardBuildTests
{
    [Theory]
    [InlineData(ImageQualityLane.Test, "Test lane (not the wipe gate).")]
    [InlineData(ImageQualityLane.Release, "Gate B wipe media")]
    public async Task Apply_uses_the_approved_composition(
        ImageQualityLane lane,
        string expectedHint)
    {
        string root = NewRoot();
        try
        {
            HostComposition composition = await Compose(root, lane);
            WizardBuildResult result = await WizardBuild.TryApplyAsync(
                composition,
                new ImageServicingTestFakes.RecordingElevatedPlanRunner(),
                TestContext.Current.CancellationToken);

            Assert.True(result.Succeeded, $"{result.Code}: {result.Message}");
            Assert.Contains(expectedHint, result.Message, StringComparison.Ordinal);
            Assert.Equal(composition.OutputIsoPath, result.OutputIsoPath);
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public async Task Apply_failure_preserves_work_and_surfaces_failure()
    {
        string root = NewRoot();
        try
        {
            HostComposition composition = await Compose(root, ImageQualityLane.Test);
            WizardBuildResult result = await WizardBuild.TryApplyAsync(
                composition,
                new ImageServicingTestFakes.FailingElevatedPlanRunner(),
                TestContext.Current.CancellationToken);

            Assert.False(result.Succeeded);
            Assert.Equal("servicing.stage.failed", result.Code);
            Assert.Contains(composition.WorkDirectory, result.Message, StringComparison.Ordinal);
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    private static async Task<HostComposition> Compose(string root, ImageQualityLane lane)
    {
        string iso = Path.Combine(root, "source.iso");
        File.WriteAllText(iso, "iso-stub");
        Result<HostComposition, HostComposeError> result = await HostCompile.ComposeAsync(
            Profile(),
            new HostComposeOptions(
                iso,
                lane,
                Path.Combine(root, "work"),
                WimIndex: 1),
            new FixedProbe(),
            cancellationToken: TestContext.Current.CancellationToken);
        Assert.True(result.IsOk, result.IsOk ? null : result.Error.Message);
        return result.Value;
    }

    private static Profile Profile() =>
        new(
            new AccountProfile("winmint", "lab-only", false),
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

    private static string NewRoot()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-wizard-build-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        return root;
    }

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
                new(
                    Path.GetFullPath(sourceIsoPath),
                    TestIso.Identity(sourceIsoPath),
                    Array.AsReadOnly([row]),
                    new(wimIndex, row.Name, row.Architecture, row.Edition, row.Version, row.Build))));
        }
    }
}
