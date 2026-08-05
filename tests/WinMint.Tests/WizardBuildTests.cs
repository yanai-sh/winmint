using WinMint.Orchestrator;
using WinMint.Wizard;

namespace WinMint.Tests;

public class WizardBuildTests
{
    [Fact]
    public void TryApply_missing_profile_fails_closed()
    {
        WizardBuildResult result = WizardBuild.TryApply(
            new WizardBuildInput(
                ProfilePath: Path.Combine(Path.GetTempPath(), "winmint-no-such-profile.json"),
                SourceIsoPath: Path.GetTempFileName()),
            new ImageServicingTestFakes.RecordingElevatedPlanRunner(),
            TestContext.Current.CancellationToken);

        Assert.False(result.Succeeded);
        Assert.Equal("wizard.build.profile.missing", result.Code);
    }

    [Fact]
    public void TryApply_missing_iso_fails_closed()
    {
        string profile = WriteTempProfile();
        try
        {
            WizardBuildResult result = WizardBuild.TryApply(
                new WizardBuildInput(
                    profile,
                    SourceIsoPath: Path.Combine(Path.GetTempPath(), "no-such.iso")),
                new ImageServicingTestFakes.RecordingElevatedPlanRunner(),
                TestContext.Current.CancellationToken);

            Assert.False(result.Succeeded);
            Assert.Equal("wizard.build.sourceIso.missing", result.Code);
        }
        finally
        {
            File.Delete(profile);
        }
    }

    [Fact]
    public void TryApply_with_fake_runner_succeeds()
    {
        string profile = WriteTempProfile();
        string iso = Path.GetTempFileName();
        string work = Path.Combine(Path.GetTempPath(), "winmint-wizard-build-" + Guid.NewGuid().ToString("N"));
        try
        {
            File.WriteAllText(iso, "iso-stub");
            WizardBuildResult result = WizardBuild.TryApply(
                new WizardBuildInput(
                    profile,
                    iso,
                    ImageQualityText: "Test",
                    WorkDirectory: work,
                    WimIndex: HostEdition.HomeWimIndex),
                new ImageServicingTestFakes.RecordingElevatedPlanRunner(),
                TestContext.Current.CancellationToken);

            Assert.True(result.Succeeded, $"{result.Code}: {result.Message}");
            Assert.NotNull(result.OutputIsoPath);
            Assert.Equal(work, result.WorkDirectory);
            Assert.Contains("Image OK:", result.Message, StringComparison.Ordinal);
        }
        finally
        {
            File.Delete(profile);
            File.Delete(iso);
            if (Directory.Exists(work))
            {
                Directory.Delete(work, recursive: true);
            }
        }
    }

    [Fact]
    public void TryApply_propagates_runner_failure()
    {
        string profile = WriteTempProfile();
        string iso = Path.GetTempFileName();
        string work = Path.Combine(Path.GetTempPath(), "winmint-wizard-build-fail-" + Guid.NewGuid().ToString("N"));
        try
        {
            File.WriteAllText(iso, "iso-stub");
            WizardBuildResult result = WizardBuild.TryApply(
                new WizardBuildInput(profile, iso, WorkDirectory: work),
                new ImageServicingTestFakes.FailingElevatedPlanRunner(),
                TestContext.Current.CancellationToken);

            Assert.False(result.Succeeded);
            Assert.Equal("servicing.stage.failed", result.Code);
            Assert.Contains(work, result.Message, StringComparison.Ordinal);
        }
        finally
        {
            File.Delete(profile);
            File.Delete(iso);
            if (Directory.Exists(work))
            {
                Directory.Delete(work, recursive: true);
            }
        }
    }

    private static string WriteTempProfile()
    {
        Profile profile = new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true)),
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            []);
        string path = Path.Combine(Path.GetTempPath(), "winmint-wizard-build-" + Guid.NewGuid().ToString("N") + ".json");
        File.WriteAllBytes(path, BuildPlan.SerializeProfile(profile));
        return path;
    }
}
