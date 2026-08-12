using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WinMint.Orchestrator;

namespace WinMint.Wizard.ViewModels;

public interface IReviewStageViewModel
{
    ReviewSummaryViewModel Summary { get; }
    ReviewBuildViewModel Build { get; }
    StageStatusViewModel Status { get; }
    IAsyncRelayCommand ReplanCommand { get; }
    IAsyncRelayCommand SaveProfileCommand { get; }
    IAsyncRelayCommand BuildCommand { get; }
    IRelayCommand CancelBuildCommand { get; }
}

internal interface IReviewStageHost
{
    Task ReplanAsync();
    Task SaveProfileAsync(CancellationToken cancellationToken);
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
    string BuildRecipe);

public sealed partial class ReviewBuildViewModel : ObservableObject
{
    [ObservableProperty] private bool _isBusy;
    [ObservableProperty] private bool _canBuild;
    [ObservableProperty] private string _buildStatus = "";
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
        Summary = new(
            IncludedSummary.FormatQuietSummary(review.RemoveProvisionedAppx.Count),
            IncludedSummary.FormatPickStrip(review.AuthoredSelectionLabels),
            IncludedSummary.FormatQuietBlock(review.BraveSelected),
            IncludedSummary.FormatWhatsIncluded(review.RemoveProvisionedAppx),
            $"Account {review.AuthoredProfile.Account.Username.Trim()} · region {review.AuthoredProfile.Dma.Settle.Locale} / {review.AuthoredProfile.Dma.Settle.TimeZoneId} · network {(review.RequiresNetwork ? "needed" : "not needed")} · DMA {(review.AuthoredProfile.Dma.Enabled ? "on" : "off")} · {review.ImageQuality} lane",
            PlanDiff.Format(review),
            $"Plan OK. Lane={review.ImageQuality}; removeProvisionedAppx={review.RemoveProvisionedAppx.Count}; jobs={review.Jobs.Count}.",
            review.AuthoredProfileJson,
            review.SourceMedia?.SourceIsoPath ?? "",
            review.OutputIsoPath,
            review.OutputIsoPath is null ? "" : $"Output ISO: {review.OutputIsoPath}");
        Status.Set(Summary.PlanSummary, false);
        Build.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(ReviewBuildViewModel.IsBusy))
            {
                ReplanCommand.NotifyCanExecuteChanged();
                SaveProfileCommand.NotifyCanExecuteChanged();
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

    [RelayCommand]
    private Task BuildAsync() => _host?.BuildAsync() ?? Task.CompletedTask;

    [RelayCommand]
    private void CancelBuild() => _host?.CancelBuild();

}
