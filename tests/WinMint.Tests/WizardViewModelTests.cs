using WinMint.Orchestrator;
using WinMint.Wizard;
using WinMint.Wizard.ViewModels;

namespace WinMint.Tests;

/// <summary>Wizard behavior through the shell and each stage's public binding interface.</summary>
public class WizardViewModelTests
{
    [Fact]
    public async Task Replan_reports_an_unknown_chip_key_as_status_instead_of_throwing()
    {
        using WizardViewModel vm = Vm();
        vm.Software.Chips.Browsers.Add(new ChipItem("not-in-catalog", "Nope", isSelected: true));

        await vm.ReplanAsync();

        Assert.True(vm.Source.Status.IsError);
        Assert.Contains("packages.catalog.unknown", vm.Source.Status.Message, StringComparison.Ordinal);
        Assert.Contains("not-in-catalog", vm.Source.Status.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Close_without_a_host_window_is_a_no_op()
    {
        using WizardViewModel vm = Vm();

        vm.CloseCommand.Execute(null);
    }

    [Fact]
    public async Task Picker_recovers_missing_default_preview_is_redacted_and_invalid_raw_edit_revokes_apply()
    {
        string iso = Path.Combine(Path.GetTempPath(), "winmint-picker-" + Guid.NewGuid().ToString("N") + ".iso");
        File.WriteAllText(iso, "iso-stub");
        try
        {
            PickerProbe probe = new();
            using WizardViewModel vm = new(storage: null, close: null, sourceMedia: probe);
            vm.Account.Password = "do-not-show-me";
            vm.Source.SourceIsoPath = iso;
            await WaitForProbeAsync(vm);

            WimIndexInfo available = Assert.Single(vm.Source.WimIndexes);
            Assert.True(vm.Source.IsWimPickerVisible);
            Assert.Null(vm.Source.SelectedWimIndex);
            Assert.Contains("wim.probe.indexMissing", vm.Source.Status.Message, StringComparison.Ordinal);

            vm.Source.SelectedWimIndex = available;
            await vm.ReplanAsync();

            Assert.True(vm.CanBuild);
            Assert.DoesNotContain("do-not-show-me", vm.Review!.Summary.PreviewJson, StringComparison.Ordinal);
            Assert.DoesNotContain("\"password\"", vm.Review.Summary.PreviewJson, StringComparison.OrdinalIgnoreCase);
            Assert.Contains("\"username\": \"winmint\"", vm.Review.Summary.PreviewJson, StringComparison.Ordinal);

            vm.Account.GeoId = "not-an-integer";

            Assert.False(vm.CanBuild);
            Assert.Null(vm.Review);
        }
        finally
        {
            File.Delete(iso);
        }
    }

    [Fact]
    public async Task Source_stage_retries_stale_probe_after_unrelated_draft_revision()
    {
        string iso = Path.Combine(Path.GetTempPath(), "winmint-probe-retry-" + Guid.NewGuid().ToString("N") + ".iso");
        File.WriteAllText(iso, "iso-stub");
        try
        {
            QueuedProbe probe = new();
            using WizardViewModel vm = new(storage: null, close: null, sourceMedia: probe);
            vm.Source.SourceIsoPath = iso;
            await probe.WaitForCallsAsync(1);

            vm.Account.Username = "unrelated-revision";
            probe.Complete(0);
            await probe.WaitForCallsAsync(2);

            Assert.True(vm.Source.IsWimProbeBusy);
            probe.Complete(1);
            await WaitForProbeAsync(vm);

            Assert.True(vm.Source.IsWimPickerVisible);
            Assert.NotNull(vm.Source.SelectedWimIndex);
            Assert.Single(vm.Source.WimIndexes);
        }
        finally
        {
            File.Delete(iso);
        }
    }

    private static WizardViewModel Vm() => new(storage: null, close: null, sourceMedia: null);

    private static async Task WaitForProbeAsync(WizardViewModel vm)
    {
        for (int i = 0; i < 100 && vm.Source.IsWimProbeBusy; i++)
        {
            await Task.Delay(10, TestContext.Current.CancellationToken);
        }
        Assert.False(vm.Source.IsWimProbeBusy);
    }

    private sealed class PickerProbe : ISourceMediaProbe
    {
        private static WimIndexInfo Available { get; } =
            new(7, "Windows 11 Pro", "aarch64", "Professional", "10.0.26100.1", "26100");

        public Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> ListIndexesAsync(
            string sourceIsoPath,
            CancellationToken cancellationToken = default) =>
            TestIso.List(Available);

        public Task<Result<SourceMediaReview, Failure>> ProbeAsync(
            string sourceIsoPath,
            int wimIndex,
            CancellationToken cancellationToken = default)
        {
            SelectedWim? selected = wimIndex == Available.Index
                ? new(
                    Available.Index,
                    Available.Name,
                    Available.Architecture,
                    Available.Edition,
                    Available.Version,
                    Available.Build)
                : null;
            return Task.FromResult(Result.Ok<SourceMediaReview, Failure>(
                new(
                    Path.GetFullPath(sourceIsoPath),
                    TestIso.Identity(sourceIsoPath),
                    Array.AsReadOnly([Available]),
                    selected,
                    selected is null
                        ? new(
                            wimIndex,
                            "wim.probe.indexMissing",
                            $"Source ISO does not contain WIM index {wimIndex}.")
                        : null)));
        }
    }

    private sealed class QueuedProbe : ISourceMediaProbe
    {
        private readonly List<TaskCompletionSource<Result<IReadOnlyList<WimIndexInfo>, Failure>>> _calls = [];

        public Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> ListIndexesAsync(
            string sourceIsoPath,
            CancellationToken cancellationToken = default)
        {
            TaskCompletionSource<Result<IReadOnlyList<WimIndexInfo>, Failure>> completion =
                new(TaskCreationOptions.RunContinuationsAsynchronously);
            _calls.Add(completion);
            return completion.Task;
        }

        public Task<Result<SourceMediaReview, Failure>> ProbeAsync(
            string sourceIsoPath,
            int wimIndex,
            CancellationToken cancellationToken = default)
        {
            WimIndexInfo row = new(wimIndex, "Windows 11 Pro", "arm64", "Professional", "10.0.26100.1", "26100");
            return Task.FromResult(Result.Ok<SourceMediaReview, Failure>(
                new(
                    Path.GetFullPath(sourceIsoPath),
                    TestIso.Identity(sourceIsoPath),
                    [row],
                    new(row.Index, row.Name, row.Architecture, row.Edition, row.Version, row.Build))));
        }

        public async Task WaitForCallsAsync(int count)
        {
            for (int i = 0; i < 100 && _calls.Count < count; i++)
            {
                await Task.Delay(10, TestContext.Current.CancellationToken);
            }
            Assert.True(_calls.Count >= count, $"Expected {count} probe calls, got {_calls.Count}.");
        }

        public void Complete(int call)
        {
            WimIndexInfo row = new(
                BuildMachineEdition.DefaultWimIndex(),
                "Windows 11 Pro",
                "arm64",
                "Professional",
                "10.0.26100.1",
                "26100");
            _calls[call].SetResult(Result.Ok<IReadOnlyList<WimIndexInfo>, Failure>([row]));
        }
    }
}
