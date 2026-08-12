using Avalonia.Controls;
using Avalonia.Platform.Storage;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WinMint.Contracts;
using WinMint.Orchestrator;

namespace WinMint.Wizard.ViewModels;

/// <summary>Wizard navigation and one Living Draft composition handle; stage authoring stays in stage view models.</summary>
public sealed partial class WizardShellViewModel :
    ObservableObject,
    IDisposable,
    ISourceStageHost,
    IReviewStageHost
{
    private const int SourceIndex = 0, AccountIndex = 1, SoftwareIndex = 2, ReviewIndex = 3;
    private static readonly string[] StageNames = ["Source", "Account", "Software", "Review"];

    private readonly IStorageProvider? _storage;
    private readonly Action? _close;
    private readonly WizardSession _session;
    private readonly SourceStageViewModel _source;
    private readonly AccountStageViewModel _account;
    private readonly SoftwareStageViewModel _software;
    private readonly Func<HostComposition, CancellationToken, Task<WizardBuildResult>> _apply;
    private ReviewStageViewModel? _reviewStage;
    private CancellationTokenSource? _buildCts;
    private bool _ready;

    public WizardShellViewModel(Window window)
        : this(window.StorageProvider, window.Close, sourceMedia: null)
    {
    }

    internal WizardShellViewModel(
        IStorageProvider? storage,
        Action? close,
        ISourceMediaProbe? sourceMedia,
        Func<HostComposition, CancellationToken, Task<WizardBuildResult>>? apply = null)
    {
        _storage = storage;
        _close = close;
        _session = new WizardSession(sourceMedia);
        _apply = apply ?? ((composition, cancellationToken) =>
            WizardBuild.TryApplyAsync(composition, cancellationToken: cancellationToken));
        _source = new SourceStageViewModel(storage, this);
        _account = new AccountStageViewModel(DraftChanged);
        _software = new SoftwareStageViewModel(DraftChanged, UseDefaultsAsync);
        _ready = true;
        SyncDraft();
        RefreshNavigation();
    }

    public ISourceStageViewModel Source => _source;
    public IAccountStageViewModel Account => _account;
    public ISoftwareStageViewModel Software => _software;
    [ObservableProperty] private IReviewStageViewModel? _review;

    [ObservableProperty] private int _stepIndex;
    [ObservableProperty] private string _stageLabel = "Source";
    [ObservableProperty] private double _progressFraction = 0.25;
    [ObservableProperty] private bool _canGoBack;
    [ObservableProperty] private bool _canGoNext;
    [ObservableProperty] private string _nextLabel = "Continue";
    [ObservableProperty] private bool _canGoToSource = true;
    [ObservableProperty] private bool _canGoToAccount;
    [ObservableProperty] private bool _canGoToSoftware;
    [ObservableProperty] private bool _canGoToReview;
    [ObservableProperty] private bool _canBuild;
    [ObservableProperty] private bool _isBusy;

    public bool IsSourceStep => StepIndex == SourceIndex;
    public bool IsAccountStep => StepIndex == AccountIndex;
    public bool IsSoftwareStep => StepIndex == SoftwareIndex;
    public bool IsReviewStep => StepIndex == ReviewIndex;

    partial void OnStepIndexChanged(int value) => RefreshNavigation();

    partial void OnIsBusyChanged(bool value)
    {
        if (_reviewStage is not null)
        {
            _reviewStage.Build.IsBusy = value;
        }
        RefreshNavigation();
        RefreshCanBuild();
    }

    [RelayCommand]
    private void Back()
    {
        if (StepIndex > SourceIndex)
        {
            StepIndex--;
        }
    }

    [RelayCommand]
    private async Task Next()
    {
        if (!CanAdvance(StepIndex))
        {
            ReportGateError(StepIndex == SoftwareIndex || StepIndex == ReviewIndex);
            return;
        }
        if (StepIndex == SoftwareIndex)
        {
            await TryEnterReviewAsync().ConfigureAwait(true);
        }
        else
        {
            StepIndex++;
        }
    }

    [RelayCommand] private Task GoToSource() => GoToStageAsync(SourceIndex);
    [RelayCommand] private Task GoToAccount() => GoToStageAsync(AccountIndex);
    [RelayCommand] private Task GoToSoftware() => GoToStageAsync(SoftwareIndex);
    [RelayCommand] private Task GoToReview() => GoToStageAsync(ReviewIndex);

    private async Task GoToStageAsync(int targetIndex)
    {
        if (targetIndex == StepIndex)
        {
            return;
        }
        if (!CanGoTo(targetIndex))
        {
            ReportGateError(targetIndex == ReviewIndex);
            return;
        }
        if (targetIndex == ReviewIndex)
        {
            await TryEnterReviewAsync().ConfigureAwait(true);
        }
        else
        {
            StepIndex = targetIndex;
        }
    }

    private async Task UseDefaultsAsync()
    {
        _software.ResetToDefaults();
        if (!CanGoTo(ReviewIndex))
        {
            StepIndex = AccountIndex;
            ReportGateError(identityRequired: true);
            return;
        }
        await TryEnterReviewAsync().ConfigureAwait(true);
    }

    private async Task<bool> TryEnterReviewAsync()
    {
        if (!await RunPlanAsync().ConfigureAwait(true))
        {
            return false;
        }
        StepIndex = ReviewIndex;
        return true;
    }

    public async Task ReplanAsync()
    {
        if (!IsBusy)
        {
            await RunPlanAsync().ConfigureAwait(true);
        }
    }

    private async Task<bool> RunPlanAsync()
    {
        if (IsBusy)
        {
            return false;
        }
        Result<WizardDraft, Failure> draft = BuildDraft();
        if (!draft.IsOk)
        {
            ReportCurrentError(draft.Error.Code, draft.Error.Message);
            InvalidatePresentation();
            return false;
        }

        _session.UpdateDraft(draft.Value.Profile, draft.Value.Options);
        Result<HostReview, Failure> planned =
            await _session.PlanAsync().ConfigureAwait(true);
        if (!planned.IsOk)
        {
            ReportCurrentError(planned.Error.Code, planned.Error.Message);
            InvalidatePresentation();
            RefreshCanBuild();
            return false;
        }

        _reviewStage = new ReviewStageViewModel(planned.Value);
        _reviewStage.Connect(this);
        Review = _reviewStage;
        RefreshCanBuild();
        return true;
    }

    public async Task SaveProfileAsync(CancellationToken cancellationToken)
    {
        if (IsBusy)
        {
            return;
        }
        if (!await RunPlanAsync().ConfigureAwait(true))
        {
            return;
        }
        if (_storage is null)
        {
            ReportCurrentError("wizard.save.storage", "Save failed: no storage provider.");
            return;
        }

        IStorageFile? file = await _storage.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Save WinMint Profile",
            SuggestedFileName = "winmint.profile.json",
            FileTypeChoices = [new FilePickerFileType("Profile JSON") { Patterns = ["*.json"] }],
        }).ConfigureAwait(true);
        cancellationToken.ThrowIfCancellationRequested();
        string? path = file?.TryGetLocalPath();
        if (file is null)
        {
            return;
        }
        if (string.IsNullOrEmpty(path))
        {
            ReportCurrentError("wizard.save.path", "Save failed: could not resolve local path.");
            return;
        }

        Result<Unit, Failure> saved = _session.Save(path);
        if (!saved.IsOk)
        {
            ReportCurrentError(saved.Error.Code, saved.Error.Message);
            return;
        }
        _reviewStage!.Build.SaveStatus = $"Saved → {path}";
        _reviewStage.Status.Set(_reviewStage.Build.SaveStatus, false);
        RefreshCanBuild();
    }

    [RelayCommand]
    public async Task BuildAsync()
    {
        if (!CanBuild || _reviewStage is null)
        {
            return;
        }

        SyncDraft();
        Result<HostComposition, Failure> approved = _session.TryGetApplyComposition();
        if (!approved.IsOk)
        {
            ReportCurrentError(approved.Error.Code, approved.Error.Message);
            return;
        }

        HostComposition composition = approved.Value;
        ReviewStageViewModel buildStage = _reviewStage;
        Directory.CreateDirectory(composition.WorkDirectory);
        _buildCts?.Cancel();
        _buildCts?.Dispose();
        _buildCts = new CancellationTokenSource();
        CancellationToken cancellationToken = _buildCts.Token;

        IsBusy = true;
        buildStage.Build.FlashGuidanceText = "";
        buildStage.Build.BuildStatus = "Building… (approve UAC if prompted)";
        buildStage.Status.Set(buildStage.Build.BuildStatus, false);

        using CancellationTokenSource pollCts =
            CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        Task pollTask = PollApplyStatusAsync(
            ApplyStatusReader.StatusPath(composition.WorkDirectory),
            buildStage,
            pollCts.Token);
        WizardBuildResult result;
        try
        {
            result = await _apply(composition, cancellationToken)
                .ConfigureAwait(true);
        }
        finally
        {
            await pollCts.CancelAsync().ConfigureAwait(true);
            try
            {
                await pollTask.ConfigureAwait(true);
            }
            catch (OperationCanceledException)
            {
            }
        }

        IsBusy = false;
        buildStage.Build.IsBusy = false;
        if (cancellationToken.IsCancellationRequested && !result.Succeeded)
        {
            buildStage.Build.BuildStatus = "Build cancelled.";
            buildStage.Status.Set(buildStage.Build.BuildStatus, true);
            return;
        }

        buildStage.Build.BuildStatus = result.Message;
        buildStage.Status.Set(result.Message, !result.Succeeded);
        if (result.Succeeded)
        {
            Result<Unit, Failure> acknowledged = _session.AcknowledgeApplySuccess(composition);
            if (!acknowledged.IsOk)
            {
                buildStage.Build.BuildStatus =
                    $"{acknowledged.Error.Code}: {acknowledged.Error.Message}";
                buildStage.Build.FlashGuidanceText = "";
                buildStage.Status.Set(buildStage.Build.BuildStatus, true);
                _reviewStage = buildStage;
                Review = buildStage;
                RefreshCanBuild();
                return;
            }
            buildStage.Build.SaveStatus = _session.View.SavedPath is { } savedPath
                ? $"Saved → {savedPath}\n{result.Message}"
                : result.Message;
            string? sha = result.Digests is not null
                && result.Digests.TryGetValue("outputIso.sha256", out string? digest)
                    ? digest
                    : null;
            buildStage.Build.FlashGuidanceText = FlashGuidance.Format(
                result.OutputIsoPath!,
                composition.Review.ImageQuality == ImageQualityLane.Release,
                sha);
        }
        else
        {
            buildStage.Build.FlashGuidanceText = "";
        }
        RefreshCanBuild();
    }

    private static async Task PollApplyStatusAsync(
        string statusPath,
        ReviewStageViewModel buildStage,
        CancellationToken cancellationToken)
    {
        string? last = null;
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                string? label = ApplyStatusReader.FormatBusyLabel(
                    ApplyStatusReader.TryRead(statusPath, cancellationToken));
                if (label is not null
                    && !string.Equals(label, last, StringComparison.Ordinal))
                {
                    last = label;
                    buildStage.Build.BuildStatus = label;
                    buildStage.Status.Set(
                        label,
                        label.StartsWith("Failed:", StringComparison.Ordinal));
                }
                await Task.Delay(500, cancellationToken).ConfigureAwait(true);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    [RelayCommand]
    public void CancelBuild() => _buildCts?.Cancel();

    [RelayCommand]
    private void Close() => _close?.Invoke();

    void ISourceStageHost.SourceDraftChanged() => DraftChanged();

    Task<Result<SourceMediaReview, Failure>> ISourceStageHost.SettleSourceProbeAsync(
        CancellationToken cancellationToken) =>
        _session.SettleProbeAsync(cancellationToken);

    void ISourceStageHost.ReportStageError(string code, string message) =>
        _source.Status.Set($"{code}: {message}", true);

    void ISourceStageHost.ClearSourceProbeError()
    {
        if (_source.Status.IsError
            && (_source.Status.Message.StartsWith("wim.probe.", StringComparison.Ordinal)
                || _source.Status.Message.StartsWith("sourceMedia.", StringComparison.Ordinal)))
        {
            _source.Status.Clear();
        }
    }

    private void DraftChanged()
    {
        if (!_ready)
        {
            return;
        }
        SyncDraft();
        RefreshNavigation();
        RefreshCanBuild();
    }

    private void SyncDraft()
    {
        Result<WizardDraft, Failure> draft = BuildDraft();
        if (draft.IsOk)
        {
            long before = _session.View.Revision;
            if (_session.UpdateDraft(draft.Value.Profile, draft.Value.Options) != before)
            {
                InvalidatePresentation();
            }
        }
        else
        {
            _session.InvalidateDraft();
            InvalidatePresentation();
        }
    }

    private Result<WizardDraft, Failure> BuildDraft()
    {
        Result<PackageSelection, Failure> packagesResult = _software.ResolvePackages();
        if (!packagesResult.IsOk)
        {
            return Result.Fail<WizardDraft, Failure>(packagesResult.Error);
        }
        Result<DebloatExpansion, Failure> expanded =
            DebloatPresets.TryExpand(_software.Presets.Value);
        if (!expanded.IsOk)
        {
            return Result.Fail<WizardDraft, Failure>(expanded.Error);
        }
        if (!int.TryParse(_account.GeoId.Trim(), out int geoId))
        {
            return Result.Fail<WizardDraft, Failure>(
                new Failure("dma.settle.geoId", "must be an integer."));
        }

        PackageSelection packages = packagesResult.Value;
        Profile profile = new(
            new AccountProfile(_account.Username.Trim(), _account.Password, _account.RequireWifi),
            new DmaProfile(
                _account.DmaEnabled,
                new DmaSettleTarget(
                    _account.DmaEnabled,
                    _account.Locale.Trim(),
                    geoId,
                    _account.TimeZone.Trim(),
                    _account.LocationServices)),
            DebloatMode.Online,
            expanded.Value.RemoveProvisionedAppx,
            IdList.FromMultiline(
                MergeChipAndAdvanced(packages.WingetInstallIds, _software.Advanced.Winget)),
            [],
            IdList.FromMultiline(
                MergeChipAndAdvanced(packages.ScoopInstallIds, _software.Advanced.Scoop)),
            [],
            IdList.FromMultiline(MergeChipAndAdvanced(
                packages.WslProfileTokens,
                _software.Advanced.Wsl)),
            [],
            expanded.Value.RemoveCapabilities,
            expanded.Value.DisableOptionalFeatures);
        HostComposeOptions options = new(
            _source.SourceIsoPath,
            _source.ImageQuality,
            WimIndex: _source.WimIndex,
            ProfileName: "winmint.profile.json",
            AuthoredSelectionLabels: _software.SelectedLabels().ToArray());
        return Result.Ok<WizardDraft, Failure>(new WizardDraft(profile, options));
    }

    private static string MergeChipAndAdvanced(
        IEnumerable<string> selectedChipIds,
        string? advancedMultiline)
    {
        IReadOnlyList<string> advanced = IdList.FromMultiline(advancedMultiline);
        return advanced.Count > 0
            ? string.Join(Environment.NewLine, advanced)
            : string.Join(
                Environment.NewLine,
                selectedChipIds
                    .Where(static id => !string.IsNullOrWhiteSpace(id))
                    .Select(static id => id.Trim())
                    .Distinct(StringComparer.OrdinalIgnoreCase));
    }

    private void InvalidatePresentation()
    {
        _reviewStage = null;
        Review = null;
    }

    private void ReportGateError(bool identityRequired)
    {
        CurrentStatus().Set(
            identityRequired
                ? "Add a password on Account to continue."
                : "Choose an existing Source ISO to continue.",
            true);
    }

    private void ReportCurrentError(string code, string message)
    {
        CurrentStatus().Set($"{code}: {message}", true);
    }

    private StageStatusViewModel CurrentStatus() =>
        StepIndex switch
        {
            AccountIndex => _account.Status,
            SoftwareIndex => _software.Status,
            ReviewIndex when _reviewStage is not null => _reviewStage.Status,
            _ => _source.Status,
        };

    private bool CanAdvance(int currentIndex) =>
        currentIndex switch
        {
            SourceIndex => _source.IsReady,
            AccountIndex => _source.IsReady,
            SoftwareIndex => _source.IsReady && _account.IdentityReady,
            _ => false,
        };

    private bool CanGoTo(int targetIndex) =>
        targetIndex is >= SourceIndex and <= ReviewIndex
        && (targetIndex == SourceIndex
            || (_source.IsReady && (targetIndex < ReviewIndex || _account.IdentityReady)));

    private void RefreshCanBuild()
    {
        CanBuild = _source.IsReady && _account.IdentityReady && _session.View.CanApply && !IsBusy;
        if (_reviewStage is not null)
        {
            _reviewStage.Build.CanBuild = CanBuild;
        }
    }

    private void RefreshNavigation()
    {
        CanGoBack = !IsBusy && StepIndex > SourceIndex;
        CanGoNext = !IsBusy && StepIndex < ReviewIndex && CanAdvance(StepIndex);
        NextLabel = StepIndex == ReviewIndex ? "Finish" : "Continue";
        StageLabel = StageNames[StepIndex];
        ProgressFraction = (StepIndex + 1) / (double)StageNames.Length;
        OnPropertyChanged(nameof(IsSourceStep));
        OnPropertyChanged(nameof(IsAccountStep));
        OnPropertyChanged(nameof(IsSoftwareStep));
        OnPropertyChanged(nameof(IsReviewStep));
        CanGoToSource = !IsBusy && CanGoTo(SourceIndex);
        CanGoToAccount = !IsBusy && CanGoTo(AccountIndex);
        CanGoToSoftware = !IsBusy && CanGoTo(SoftwareIndex);
        CanGoToReview = !IsBusy && CanGoTo(ReviewIndex);
    }

    public void Dispose()
    {
        _buildCts?.Cancel();
        _buildCts?.Dispose();
        _source.Dispose();
        _session.Dispose();
    }
}

internal sealed record WizardDraft(Profile Profile, HostComposeOptions Options);
