using System.Globalization;

using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

using WinMint.Contracts;
using WinMint.Orchestrator;

namespace WinMint.Wizard.ViewModels;

public interface IReviewStageViewModel
{
    ReviewSummaryViewModel Summary { get; }
    ReviewBuildViewModel Build { get; }
    StageStatusViewModel Status { get; }
    IAsyncRelayCommand ReplanCommand { get; }
    IAsyncRelayCommand SaveProfileCommand { get; }
    IAsyncRelayCommand ExportStationPackCommand { get; }
    IAsyncRelayCommand BuildCommand { get; }
    IRelayCommand CancelBuildCommand { get; }
}

internal interface IReviewStageHost
{
    Task ReplanAsync();
    Task SaveProfileAsync(CancellationToken cancellationToken);
    Task ExportStationPackAsync(CancellationToken cancellationToken);
    Task BuildAsync();
    void CancelBuild();
}

public sealed record ReviewSummaryViewModel(
    string QuietSummaryText,
    string PickStripText,
    string QuietBlockText,
    string WhatsIncludedText,
    string PlanMetaText,
    string FullPlanText,
    string PlanSummary,
    string PreviewJson,
    string SourceIsoPath,
    string? OutputIsoPath,
    string BuildRecipe,
    string AccountName,
    string EditionName,
    string WifiLabel,
    string RegionLabel);

public sealed partial class ReviewBuildViewModel : ObservableObject
{
    [ObservableProperty] private bool _isBusy;
    [ObservableProperty] private bool _canBuild;
    [ObservableProperty] private string _buildStatus = "";
    [ObservableProperty] private string _aliveLine = "";
    [ObservableProperty] private string _statusTail = "";
    [ObservableProperty] private bool _isProgressIndeterminate = true;
    [ObservableProperty] private double _progressValue;
    [ObservableProperty] private string _stepCue = "";
    [ObservableProperty] private string _failureDetail = "";
    [ObservableProperty] private string _transcriptHint = "";
    [ObservableProperty] private string _saveStatus = "";
    [ObservableProperty] private string _flashGuidanceText = "";

    public string BuildWaitHint { get; } =
        "Offline servicing can take several hours. Status updates are normal — not a stall.";
}

internal sealed partial class ReviewStageViewModel : ObservableObject, IReviewStageViewModel
{
    private IReviewStageHost? _host;

    public ReviewStageViewModel(HostReview review)
    {
        ArgumentNullException.ThrowIfNull(review);
        string gateLabel = review.IsGateB
            ? "Gate B"
            : review.ImageQuality == ImageQualityLane.Release && review.PackageStrict
                ? "not Gate B (package wire)"
                : "shipping";
        Summary = new(
            review.QuietSummary,
            review.PickStrip,
            review.QuietBlock,
            review.WhatsIncluded,
            review.PlanMeta,
            review.Diff,
            $"Plan OK. {gateLabel}; removeProvisionedAppx={review.RemoveProvisionedAppx.Count}; jobs={review.Jobs.Count}.",
            review.AuthoredProfileJson,
            review.SourceMedia?.SourceIsoPath ?? "",
            review.OutputIsoPath,
            review.OutputIsoPath is null ? "" : $"Output ISO: {review.OutputIsoPath}",
            review.AuthoredProfile.Account.Username,
            review.SourceMedia?.Selected?.Name ?? "—",
            review.AuthoredProfile.Account.RequireWifiDuringOobe ? "Required at OOBE" : "Optional",
            FormatRegion(review.AuthoredProfile.Dma.Settle));
        Status.Set(Summary.PlanSummary, false);
        Build.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(ReviewBuildViewModel.IsBusy))
            {
                ReplanCommand.NotifyCanExecuteChanged();
                SaveProfileCommand.NotifyCanExecuteChanged();
                ExportStationPackCommand.NotifyCanExecuteChanged();
            }
        };
    }

    public ReviewSummaryViewModel Summary { get; }
    public ReviewBuildViewModel Build { get; } = new();
    public StageStatusViewModel Status { get; } = new();

    internal void Connect(IReviewStageHost host) => _host = host;

    private bool CanPlan() => !Build.IsBusy;

    [RelayCommand(CanExecute = nameof(CanPlan))]
    private Task Replan() => _host?.ReplanAsync() ?? Task.CompletedTask;

    [RelayCommand(IncludeCancelCommand = true, CanExecute = nameof(CanPlan))]
    private Task SaveProfileAsync(CancellationToken cancellationToken) =>
        _host?.SaveProfileAsync(cancellationToken) ?? Task.CompletedTask;

    [RelayCommand(IncludeCancelCommand = true, CanExecute = nameof(CanPlan))]
    private Task ExportStationPackAsync(CancellationToken cancellationToken) =>
        _host?.ExportStationPackAsync(cancellationToken) ?? Task.CompletedTask;

    [RelayCommand]
    private Task BuildAsync() => _host?.BuildAsync() ?? Task.CompletedTask;

    [RelayCommand]
    private void CancelBuild() => _host?.CancelBuild();

    private static string FormatRegion(DmaSettleTarget settle)
    {
        string geo = settle.GeoId?.ToString(CultureInfo.InvariantCulture) ?? "—";
        return $"{settle.Locale ?? "—"} · {geo} · {settle.TimeZoneId ?? "—"}";
    }
}
