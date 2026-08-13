using WinMint.Orchestrator;
using WinMint.Wizard;
using WinMint.Wizard.ViewModels;

namespace WinMint.Tests;

public class WizardStageGatesTests
{
    [Fact]
    public void Stage_views_bind_through_single_digit_interfaces()
    {
        Assert.InRange(typeof(ISourceStageViewModel).GetProperties().Length, 1, 9);
        Assert.InRange(typeof(IAccountStageViewModel).GetProperties().Length, 1, 9);
        Assert.InRange(typeof(ISoftwareStageViewModel).GetProperties().Length, 1, 9);
        Assert.InRange(typeof(IReviewStageViewModel).GetProperties().Length, 1, 9);
    }

    [Fact]
    public async Task Shell_navigation_enforces_source_then_identity()
    {
        string iso = WriteIso();
        try
        {
            using WizardViewModel shell = new(null, null, new FixedProbe());
            Assert.False(shell.CanGoToAccount);
            Assert.False(shell.CanGoToReview);

            shell.Source.SourceIsoPath = iso;
            Assert.True(shell.CanGoToAccount);
            Assert.True(shell.CanGoToSoftware);
            Assert.False(shell.CanGoToReview);

            await shell.GoToAccountCommand.ExecuteAsync(null);
            Assert.True(shell.IsAccountStep);
            shell.Account.Password = "lab-only";
            Assert.True(shell.CanGoToReview);

            await shell.GoToReviewCommand.ExecuteAsync(null);
            Assert.True(shell.IsReviewStep);
            Assert.NotNull(shell.Review);
        }
        finally
        {
            File.Delete(iso);
        }
    }

    [Fact]
    public async Task Shell_build_gate_tracks_only_current_session_approval()
    {
        string iso = WriteIso();
        try
        {
            using WizardViewModel shell = new(null, null, new FixedProbe());
            shell.Source.SourceIsoPath = iso;
            shell.Account.Password = "lab-only";
            Assert.False(shell.CanBuild);

            await shell.ReplanAsync();
            Assert.True(shell.CanBuild);

            shell.Account.Username = "changed";
            Assert.False(shell.CanBuild);
            Assert.Null(shell.Review);
        }
        finally
        {
            File.Delete(iso);
        }
    }

    [Fact]
    public async Task Empty_authored_preset_leaves_effective_appx_to_HostReview()
    {
        string iso = WriteIso();
        try
        {
            using WizardViewModel shell = new(null, null, new FixedProbe());
            shell.Source.SourceIsoPath = iso;
            shell.Account.Password = "lab-only";
            shell.Software.Presets.Value = DebloatPresets.Empty;

            await shell.ReplanAsync();

            string postureApp = ProductPosture.AppxIds[0];
            Assert.DoesNotContain(postureApp, shell.Review!.Summary.PreviewJson, StringComparison.OrdinalIgnoreCase);
            Assert.Contains(postureApp, shell.Review.Summary.FullPlanText, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            File.Delete(iso);
        }
    }

    [Fact]
    public async Task Replan_command_is_disabled_during_apply_and_cannot_replace_approval()
    {
        string iso = WriteIso();
        try
        {
            TaskCompletionSource enteredApply = new(TaskCreationOptions.RunContinuationsAsynchronously);
            TaskCompletionSource releaseApply = new(TaskCreationOptions.RunContinuationsAsynchronously);
            using WizardViewModel shell = new(
                null,
                null,
                new FixedProbe(),
                async (composition, cancellationToken) =>
                {
                    enteredApply.SetResult();
                    await releaseApply.Task.WaitAsync(cancellationToken);
                    return WizardBuildResult.Ok(
                        "Image OK",
                        composition.OutputIsoPath,
                        composition.WorkDirectory,
                        new Dictionary<string, string>());
                });
            shell.Source.SourceIsoPath = iso;
            shell.Account.Password = "lab-only";
            await shell.ReplanAsync();
            IReviewStageViewModel review = shell.Review!;

            Task build = shell.BuildCommand.ExecuteAsync(null);
            await enteredApply.Task.WaitAsync(TestContext.Current.CancellationToken);

            Assert.True(shell.IsBusy);
            Assert.False(review.ReplanCommand.CanExecute(null));
            await review.ReplanCommand.ExecuteAsync(null);
            Assert.Same(review, shell.Review);

            releaseApply.SetResult();
            await build;
            Assert.False(shell.CanBuild);
            Assert.False(review.Status.IsError);
            Assert.True(review.ReplanCommand.CanExecute(null));
        }
        finally
        {
            File.Delete(iso);
        }
    }

    [Fact]
    public async Task Unexpected_apply_success_acknowledgement_failure_is_reported()
    {
        string iso = WriteIso();
        try
        {
            WizardViewModel? shell = null;
            shell = new(
                null,
                null,
                new FixedProbe(),
                (composition, _) =>
                {
                    shell!.Account.Username = "changed-during-apply";
                    return Task.FromResult(WizardBuildResult.Ok(
                        "Image OK",
                        composition.OutputIsoPath,
                        composition.WorkDirectory,
                        new Dictionary<string, string>()));
                });
            using (shell)
            {
                shell.Source.SourceIsoPath = iso;
                shell.Account.Password = "lab-only";
                await shell.ReplanAsync();

                await shell.BuildCommand.ExecuteAsync(null);

                Assert.NotNull(shell.Review);
                Assert.True(shell.Review.Status.IsError);
                Assert.Contains("wizardSession.apply.stale", shell.Review.Status.Message, StringComparison.Ordinal);
                Assert.Equal("", shell.Review.Build.FlashGuidanceText);
            }
        }
        finally
        {
            File.Delete(iso);
        }
    }

    [Fact]
    public async Task Review_preserves_authored_Edge_chip_label_without_install_job_inference()
    {
        string iso = WriteIso();
        try
        {
            using WizardViewModel shell = new(null, null, new FixedProbe());
            shell.Source.SourceIsoPath = iso;
            shell.Account.Password = "lab-only";
            shell.Software.Chips.Browsers.Single(chip => chip.Id == "edge").IsSelected = true;

            await shell.ReplanAsync();

            Assert.Contains("Edge", shell.Review!.Summary.PickStripText, StringComparison.Ordinal);
        }
        finally
        {
            File.Delete(iso);
        }
    }

    private static string WriteIso()
    {
        string path = Path.Combine(Path.GetTempPath(), "winmint-shell-" + Guid.NewGuid().ToString("N") + ".iso");
        File.WriteAllText(path, "iso-stub");
        return path;
    }

    private sealed class FixedProbe : ISourceMediaProbe
    {
        public Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> ListIndexesAsync(
            string sourceIsoPath,
            CancellationToken cancellationToken = default)
        {
            WimIndexInfo row = new(
                ImageServicing.DefaultProWimIndex,
                "Windows 11 Pro",
                "arm64",
                "Professional",
                "10.0.26100.1",
                "26100");
            return TestIso.List(row);
        }

        public Task<Result<SourceMediaReview, Failure>> ProbeAsync(
            string sourceIsoPath,
            int wimIndex,
            CancellationToken cancellationToken = default)
        {
            WimIndexInfo row = new(
                wimIndex,
                "Windows 11 Pro",
                "arm64",
                "Professional",
                "10.0.26100.1",
                "26100");
            return Task.FromResult(Result.Ok<SourceMediaReview, Failure>(
                new(
                    Path.GetFullPath(sourceIsoPath),
                    TestIso.Identity(sourceIsoPath),
                    [row],
                    new(row.Index, row.Name, row.Architecture, row.Edition, row.Version, row.Build))));
        }
    }
}
