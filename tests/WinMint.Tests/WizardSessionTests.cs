using WinMint.Contracts;
using WinMint.Orchestrator;
using WinMint.Wizard;
using WinMint.Wizard.ViewModels;

namespace WinMint.Tests;

public class WizardSessionTests
{
    [Fact]
    public async Task Living_draft_invalidates_and_only_exact_apply_success_clears_approval()
    {
        string root = NewRoot();
        try
        {
            string iso = WriteIso(root);
            WizardSession session = new(new FixedProbe());
            long first = session.UpdateDraft(
                Profile(),
                Options(root, iso) with { AuthoredSelectionLabels = ["Edge"] });
            Assert.Equal(
                first,
                session.UpdateDraft(
                    Profile(),
                    Options(root, iso) with { AuthoredSelectionLabels = ["Edge"] }));

            Result<HostReview, Failure> planned = await session.PlanAsync(TestContext.Current.CancellationToken);
            Assert.True(planned.IsOk, planned.IsOk ? null : planned.Error.Message);
            HostComposition approved = session.TryGetApplyComposition().Value;

            long changed = session.UpdateDraft(
                Profile() with { WingetPackages = ["jqlang.jq"] },
                Options(root, iso));
            Assert.True(changed > first);
            Assert.False(session.TryGetApplyComposition().IsOk);
            Assert.False(session.AcknowledgeApplySuccess(approved).IsOk);

            Assert.True((await session.PlanAsync(TestContext.Current.CancellationToken)).IsOk);
            HostComposition current = session.TryGetApplyComposition().Value;
            Result<ImageEvidence, Failure> failedApply = await HostCompile.ApplyAsync(
                current,
                new ImageServicingTestFakes.FailingElevatedPlanRunner(),
                TestContext.Current.CancellationToken);
            Assert.False(failedApply.IsOk);
            Assert.Same(current, session.TryGetApplyComposition().Value);
            Assert.True(session.AcknowledgeApplySuccess(current).IsOk);
            Assert.False(session.TryGetApplyComposition().IsOk);
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public async Task Save_is_atomic_acknowledgement_and_apply_does_not_require_it()
    {
        string root = NewRoot();
        try
        {
            string iso = WriteIso(root);
            WizardSession session = new(new FixedProbe());
            session.UpdateDraft(Profile(), Options(root, iso));
            Assert.True((await session.PlanAsync(TestContext.Current.CancellationToken)).IsOk);
            Assert.True(session.TryGetApplyComposition().IsOk);
            Assert.Null(session.View.SavedPath);

            string destination = Path.Combine(root, "saved.profile.json");
            Assert.True(session.Save(destination).IsOk);
            Assert.Equal(Path.GetFullPath(destination), session.View.SavedPath);
            Assert.True(File.Exists(destination));
            Assert.True(session.TryGetApplyComposition().IsOk);
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public async Task Late_probe_and_compose_results_are_rejected()
    {
        string root = NewRoot();
        try
        {
            string iso = WriteIso(root);
            ControlledProbe probe = new();
            WizardSession session = new(probe);
            session.UpdateDraft(Profile(), Options(root, iso));
            Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> pendingProbe =
                session.ListIndexesAsync(TestContext.Current.CancellationToken);
            session.UpdateDraft(Profile() with { RemoveCapabilities = ["OpenSSH.Client~~~~0.0.1.0"] }, Options(root, iso));
            probe.Complete(iso);
            Result<IReadOnlyList<WimIndexInfo>, Failure> staleProbe = await pendingProbe;
            Assert.False(staleProbe.IsOk);
            Assert.Equal("wizardSession.probe.stale", staleProbe.Error.Code);

            ControlledProbe composeProbe = new();
            WizardSession composeSession = new(composeProbe);
            composeSession.UpdateDraft(Profile(), Options(root, iso));
            Task<Result<HostReview, Failure>> pendingCompose =
                composeSession.PlanAsync(TestContext.Current.CancellationToken);
            composeSession.UpdateDraft(Profile() with { WingetPackages = ["jqlang.jq"] }, Options(root, iso));
            composeProbe.Complete(iso);
            Result<HostReview, Failure> staleCompose = await pendingCompose;
            Assert.False(staleCompose.IsOk);
            Assert.Equal("wizardSession.compose.stale", staleCompose.Error.Code);
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public async Task Out_of_order_source_probe_completion_keeps_the_current_session_source()
    {
        string root = NewRoot();
        try
        {
            string firstIso = WriteIso(root);
            string secondIso = Path.Combine(root, "second.iso");
            File.WriteAllText(secondIso, "second-iso-stub");
            QueuedProbe probe = new();
            WizardSession session = new(probe);

            session.UpdateDraft(Profile(), Options(root, firstIso));
            Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> first =
                session.ListIndexesAsync(TestContext.Current.CancellationToken);
            session.UpdateDraft(Profile(), Options(root, secondIso));
            Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> second =
                session.ListIndexesAsync(TestContext.Current.CancellationToken);

            probe.Complete(1, secondIso);
            Assert.True((await second).IsOk);
            probe.Complete(0, firstIso);
            Result<IReadOnlyList<WimIndexInfo>, Failure> stale = await first;

            Assert.False(stale.IsOk);
            Assert.Equal("wizardSession.probe.stale", stale.Error.Code);
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public void Software_stage_resolves_curated_chip_keys_through_the_catalog()
    {
        SoftwareStageViewModel software = new(() => { }, () => Task.CompletedTask);
        software.Chips.Browsers.Single(chip => chip.Id == "zen-browser").IsSelected = true;
        software.Chips.Editors.Single(chip => chip.Id == "cursor").IsSelected = true;
        software.Chips.Wsl.Single(chip => chip.Id == "FedoraLinux").IsSelected = true;

        Result<PackageSelection, Failure> selection = software.ResolvePackages();

        Assert.True(selection.IsOk);
        Assert.Contains("Zen-Team.Zen-Browser", selection.Value.WingetInstallIds);
        Assert.Contains("Anysphere.Cursor", selection.Value.WingetInstallIds);
        Assert.Contains("FedoraLinux", selection.Value.WslProfileTokens);
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

    private static HostComposeOptions Options(string root, string iso) =>
        new(iso, WorkDirectory: Path.Combine(root, "work"), WimIndex: 1);

    private static string NewRoot()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-session-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        return root;
    }

    private static string WriteIso(string root)
    {
        string path = Path.Combine(root, "source.iso");
        File.WriteAllText(path, "iso-stub");
        return path;
    }

    private sealed class FixedProbe : ISourceMediaProbe
    {
        public Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> ListIndexesAsync(
            string sourceIsoPath,
            CancellationToken cancellationToken = default) =>
            TestIso.List(Review(sourceIsoPath, ImageServicing.DefaultProWimIndex).Indexes[0]);

        public Task<Result<SourceMediaReview, Failure>> ProbeAsync(
            string sourceIsoPath,
            int wimIndex,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(Result.Ok<SourceMediaReview, Failure>(Review(sourceIsoPath, wimIndex)));
    }

    private sealed class ControlledProbe : ISourceMediaProbe
    {
        private readonly TaskCompletionSource<Result<IReadOnlyList<WimIndexInfo>, Failure>> _list =
            new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly TaskCompletionSource<Result<SourceMediaReview, Failure>> _probe =
            new(TaskCreationOptions.RunContinuationsAsynchronously);

        public Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> ListIndexesAsync(
            string sourceIsoPath,
            CancellationToken cancellationToken = default) =>
            _list.Task;

        public Task<Result<SourceMediaReview, Failure>> ProbeAsync(
            string sourceIsoPath,
            int wimIndex,
            CancellationToken cancellationToken = default) =>
            _probe.Task;

        public void Complete(string iso)
        {
            SourceMediaReview review = Review(iso, 1);
            _list.TrySetResult(Result.Ok<IReadOnlyList<WimIndexInfo>, Failure>(review.Indexes));
            _probe.TrySetResult(Result.Ok<SourceMediaReview, Failure>(review));
        }
    }

    private sealed class QueuedProbe : ISourceMediaProbe
    {
        private readonly List<TaskCompletionSource<Result<IReadOnlyList<WimIndexInfo>, Failure>>> _pending = [];

        public Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> ListIndexesAsync(
            string sourceIsoPath,
            CancellationToken cancellationToken = default)
        {
            TaskCompletionSource<Result<IReadOnlyList<WimIndexInfo>, Failure>> completion =
                new(TaskCreationOptions.RunContinuationsAsynchronously);
            _pending.Add(completion);
            return completion.Task;
        }

        public Task<Result<SourceMediaReview, Failure>> ProbeAsync(
            string sourceIsoPath,
            int wimIndex,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(Result.Ok<SourceMediaReview, Failure>(Review(sourceIsoPath, wimIndex)));

        public void Complete(int call, string iso) =>
            _pending[call].SetResult(Result.Ok<IReadOnlyList<WimIndexInfo>, Failure>(Review(iso, 1).Indexes));
    }

    private static SourceMediaReview Review(string iso, int index)
    {
        WimIndexInfo row = new(index, "Windows 11 Home", "ARM64", "Core", "10.0.26100.1", "26100");
        return new(
            Path.GetFullPath(iso),
            TestIso.Identity(iso),
            Array.AsReadOnly([row]),
            new(index, row.Name, row.Architecture, row.Edition, row.Version, row.Build));
    }
}
