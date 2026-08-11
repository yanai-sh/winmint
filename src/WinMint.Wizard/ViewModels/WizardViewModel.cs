using System.Collections.ObjectModel;
using Avalonia.Controls;
using Avalonia.Platform.Storage;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WinMint.Orchestrator;

namespace WinMint.Wizard.ViewModels;

/// <summary>v1-shaped wizard host — curated chips, silent account/DMA defaults, no catalog dump.</summary>
public sealed partial class WizardViewModel : ObservableObject, IDisposable
{
    private static readonly string[] StepNames = ["Source", "Account", "Software", "Review"];

    private readonly Window _window;
    private readonly int _hostWimDefault = HostEdition.DefaultWimIndex();
    private readonly IWimIndexSource? _wimIndexSource;
    private byte[]? _lastProfileUtf8;
    private bool _lastRequiresNetwork;
    private BuildArtifacts? _lastArtifacts;
    private Profile? _lastProfile;
    private string? _savedProfilePath;
    private CancellationTokenSource? _buildCts;
    private CancellationTokenSource? _probeCts;
    private int _wimIndex;
    private bool _userChoseWimIndex;
    private int _probeGeneration;

    public WizardViewModel(Window window)
        : this(window, wimIndexSource: null)
    {
    }

    internal WizardViewModel(Window window, IWimIndexSource? wimIndexSource)
    {
        _window = window;
        _wimIndexSource = wimIndexSource;
        _wimIndex = _hostWimDefault;

        BrowserChips = ToChips(
        [
            ("zen-browser", "Zen"),
            ("firefox-developer-edition", "Firefox Dev"),
            ("brave", "Brave"),
            ("edge", "Edge"),
        ]);
        EditorChips = ToChips(
        [
            ("cursor", "Cursor"),
            ("vscode", "VS Code"),
            ("zed", "Zed"),
            ("neovim", "Neovim"),
        ]);
        ShellChips =
        [
            new("windhawk", "Windhawk"),
            new("yasb", "YASB"),
            new("komorebi", "Komorebi"),
            new("fancywm", "FancyWM", isEnabled: false, toolTip: "Coming soon"),
        ];
        foreach (ChipItem chip in ShellChips)
        {
            chip.IsSelected = false;
        }

        WslChips = ToChips(
        [
            ("Ubuntu", "Ubuntu"),
            ("FedoraLinux", "Fedora"),
            ("archlinux", "Arch"),
            ("NixOS-WSL", "NixOS"),
            ("pengwin", "Pengwin"),
        ]);

        ApplyHostDmaDefaults();
        RefreshNav();
    }

    public ObservableCollection<ChipItem> BrowserChips { get; }
    public ObservableCollection<ChipItem> EditorChips { get; }
    public ObservableCollection<ChipItem> ShellChips { get; }
    public ObservableCollection<ChipItem> WslChips { get; }

    [ObservableProperty] private int _stepIndex;
    [ObservableProperty] private string _stageLabel = "Source";
    [ObservableProperty] private double _progressFraction = 0.25;
    [ObservableProperty] private bool _canGoBack;
    [ObservableProperty] private bool _canGoNext = true;
    [ObservableProperty] private string _nextLabel = "Continue";
    [ObservableProperty] private bool _canGoToSource = true;
    [ObservableProperty] private bool _canGoToAccount;
    [ObservableProperty] private bool _canGoToSoftware;
    [ObservableProperty] private bool _canGoToReview;

    [ObservableProperty] private string _sourceIsoPath = "";
    [ObservableProperty] private string _imageQuality = "Test";
    [ObservableProperty] private string _preset = DebloatPresets.Recommended;

    public ObservableCollection<WimIndexInfo> WimIndexes { get; } = [];
    [ObservableProperty] private WimIndexInfo? _selectedWimIndex;
    [ObservableProperty] private bool _isWimPickerVisible;
    [ObservableProperty] private bool _isWimProbeBusy;

    [ObservableProperty] private string _username = "winmint";
    [ObservableProperty] private string _password = "";
    [ObservableProperty] private bool _requireWifi;
    [ObservableProperty] private bool _dmaEnabled = true;
    [ObservableProperty] private string _locale = "en-GB";
    [ObservableProperty] private string _geoId = "242";
    [ObservableProperty] private string _timeZone = "GMT Standard Time";
    [ObservableProperty] private bool _locationServices = true;

    /// <summary>Power-user multiline overrides (install ids / WSL tokens). Empty ⇒ curated chips only.</summary>
    [ObservableProperty] private string _advancedWingetText = "";
    [ObservableProperty] private string _advancedScoopText = "";
    [ObservableProperty] private string _advancedWslText = "";

    [ObservableProperty] private string _status = "";
    [ObservableProperty] private bool _statusIsError;
    [ObservableProperty] private string _previewJson = "";
    [ObservableProperty] private string _planSummary = "";
    [ObservableProperty] private string _buildRecipe = "";

    // Review receipt layers: quiet product defaults, selected picks, effective remove-list, and plan meta.
    [ObservableProperty] private string _quietSummaryText = "";
    [ObservableProperty] private string _pickStripText = "";
    [ObservableProperty] private string _quietBlockText = "";
    [ObservableProperty] private string _whatsIncludedText = "";
    [ObservableProperty] private string _planMetaText = "";
    [ObservableProperty] private string _fullPlanText = "";
    [ObservableProperty] private string _saveStatus = "";
    [ObservableProperty] private bool _canBuild;
    [ObservableProperty] private bool _isBusy;
    [ObservableProperty] private string _buildStatus = "";
    [ObservableProperty] private string? _outputIsoPath;

    public bool IsSourceStep => StepIndex == WizardStageGates.Source;
    public bool IsAccountStep => StepIndex == WizardStageGates.Account;
    public bool IsSoftwareStep => StepIndex == WizardStageGates.Software;
    public bool IsReviewStep => StepIndex == WizardStageGates.Review;

    public bool IsEmptyPreset => string.Equals(Preset, DebloatPresets.Empty, StringComparison.OrdinalIgnoreCase);
    public bool IsAcceptancePreset => string.Equals(Preset, DebloatPresets.Acceptance, StringComparison.OrdinalIgnoreCase);
    public bool IsRecommendedPreset => string.Equals(Preset, DebloatPresets.Recommended, StringComparison.OrdinalIgnoreCase);
    public bool IsTestLane => string.Equals(ImageQuality, "Test", StringComparison.OrdinalIgnoreCase);
    public bool IsReleaseLane => string.Equals(ImageQuality, "Release", StringComparison.OrdinalIgnoreCase);

    partial void OnStepIndexChanged(int value) => RefreshNav();

    partial void OnSourceIsoPathChanged(string value)
    {
        RefreshNav();
        RefreshCanBuild();
        _ = ProbeSourceWimAsync();
    }

    partial void OnSelectedWimIndexChanged(WimIndexInfo? value)
    {
        if (value is null)
        {
            return;
        }

        if (value.Index != _wimIndex)
        {
            _userChoseWimIndex = true;
        }

        _wimIndex = value.Index;
        RefreshRecipe();
    }

    partial void OnIsBusyChanged(bool value)
    {
        RefreshNav();
        RefreshCanBuild();
    }

    partial void OnUsernameChanged(string value)
    {
        RefreshNav();
        RefreshCanBuild();
    }

    partial void OnPasswordChanged(string value)
    {
        RefreshNav();
        RefreshCanBuild();
    }

    partial void OnPresetChanged(string value)
    {
        OnPropertyChanged(nameof(IsEmptyPreset));
        OnPropertyChanged(nameof(IsAcceptancePreset));
        OnPropertyChanged(nameof(IsRecommendedPreset));
    }

    partial void OnImageQualityChanged(string value)
    {
        OnPropertyChanged(nameof(IsTestLane));
        OnPropertyChanged(nameof(IsReleaseLane));
    }

    [RelayCommand] private void SelectEmptyPreset() => Preset = DebloatPresets.Empty;
    [RelayCommand] private void SelectAcceptancePreset() => Preset = DebloatPresets.Acceptance;
    [RelayCommand] private void SelectRecommendedPreset() => Preset = DebloatPresets.Recommended;

    [RelayCommand]
    private void UseHostDma() => ApplyHostDmaDefaults();

    private void ApplyHostDmaDefaults()
    {
        HostDmaSnapshot snap = HostDma.Capture();
        Locale = snap.Locale;
        GeoId = snap.GeoId.ToString(System.Globalization.CultureInfo.InvariantCulture);
        TimeZone = snap.TimeZoneId;
        LocationServices = snap.LocationServicesEnabled;
    }

    [RelayCommand] private void SelectTestLane() => ImageQuality = "Test";
    [RelayCommand] private void SelectReleaseLane() => ImageQuality = "Release";

    [RelayCommand]
    private async Task BrowseIsoAsync()
    {
        IStorageProvider? storage = _window.StorageProvider;
        if (storage is null)
        {
            return;
        }

        IReadOnlyList<IStorageFile> files = await storage.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Choose Source ISO",
            AllowMultiple = false,
            FileTypeFilter = [new FilePickerFileType("ISO") { Patterns = ["*.iso"] }],
        }).ConfigureAwait(true);

        if (files.Count > 0)
        {
            string? path = files[0].TryGetLocalPath();
            if (!string.IsNullOrEmpty(path))
            {
                // Path change triggers probe via OnSourceIsoPathChanged.
                _userChoseWimIndex = false;
                SourceIsoPath = path;
                Status = "";
                StatusIsError = false;
            }
        }
    }

    [RelayCommand]
    private void Back()
    {
        // Free within visited — no gate on the way back.
        if (StepIndex > WizardStageGates.Source)
        {
            StepIndex--;
        }
    }

    [RelayCommand]
    private void Next()
    {
        if (StepIndex >= WizardStageGates.Review)
        {
            return;
        }

        if (!WizardStageGates.CanAdvance(StepIndex, SourceIsoReady(), IdentityReadyNow()))
        {
            Status = StepIndex == WizardStageGates.Software
                ? "Add a password on Account to continue."
                : "Choose an existing Source ISO to continue.";
            StatusIsError = true;
            return;
        }

        if (StepIndex == WizardStageGates.Software)
        {
            TryEnterReview();
            return;
        }

        StepIndex++;
    }

    // Stage scrub — status-bar Source/Account/Software/Review labels jump directly via WizardStageGates.CanGoTo.
    [RelayCommand] private void GoToSource() => GoToStage(WizardStageGates.Source);
    [RelayCommand] private void GoToAccount() => GoToStage(WizardStageGates.Account);
    [RelayCommand] private void GoToSoftware() => GoToStage(WizardStageGates.Software);
    [RelayCommand] private void GoToReview() => GoToStage(WizardStageGates.Review);

    private void GoToStage(int targetIndex)
    {
        if (targetIndex == StepIndex)
        {
            return;
        }

        if (!WizardStageGates.CanGoTo(targetIndex, SourceIsoReady(), IdentityReadyNow()))
        {
            Status = targetIndex == WizardStageGates.Review
                ? "Add a password on Account to continue."
                : "Choose an existing Source ISO to continue.";
            StatusIsError = true;
            return;
        }

        if (targetIndex == WizardStageGates.Review)
        {
            // Entering Review from stage navigation composes the same receipt as Next.
            TryEnterReview();
            return;
        }

        StepIndex = targetIndex;
    }

    /// <summary>Software skip — recommended preset, clear package chips, jump to Review.</summary>
    [RelayCommand]
    private void UseDefaults()
    {
        Preset = DebloatPresets.Recommended;
        foreach (ChipItem chip in BrowserChips.Concat(EditorChips).Concat(ShellChips).Concat(WslChips))
        {
            chip.IsSelected = false;
        }

        AdvancedWingetText = "";
        AdvancedScoopText = "";
        AdvancedWslText = "";
        if (!WizardStageGates.CanGoTo(WizardStageGates.Review, SourceIsoReady(), IdentityReadyNow()))
        {
            StepIndex = WizardStageGates.Account;
            Status = "Add a password on Account to continue.";
            StatusIsError = true;
            return;
        }

        TryEnterReview();
    }

    private bool TryEnterReview()
    {
        if (!RunPlan())
        {
            return false;
        }

        StepIndex = WizardStageGates.Review;
        RefreshRecipe();
        return true;
    }

    [RelayCommand]
    private void Replan() => RunPlan();

    [RelayCommand(IncludeCancelCommand = true)]
    private async Task SaveProfileAsync(CancellationToken cancellationToken)
    {
        if (!RunPlan() || _lastProfileUtf8 is null)
        {
            return;
        }

        IStorageProvider? storage = _window.StorageProvider;
        if (storage is null)
        {
            Status = "Save failed: no storage provider.";
            StatusIsError = true;
            return;
        }

        IStorageFile? file = await storage.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Save WinMint Profile",
            SuggestedFileName = "winmint.profile.json",
            FileTypeChoices = [new FilePickerFileType("Profile JSON") { Patterns = ["*.json"] }],
        }).ConfigureAwait(true);

        if (file is null)
        {
            return;
        }

        cancellationToken.ThrowIfCancellationRequested();

        string? path = file.TryGetLocalPath();
        if (string.IsNullOrEmpty(path))
        {
            Status = "Save failed: could not resolve local path.";
            StatusIsError = true;
            return;
        }

        await File.WriteAllBytesAsync(path, _lastProfileUtf8, cancellationToken).ConfigureAwait(true);
        _savedProfilePath = path;
        SaveStatus = $"Saved → {path}";
        Status = SaveStatus;
        StatusIsError = false;
        RefreshRecipe();
        RefreshCanBuild();
    }

    [RelayCommand]
    private async Task BuildAsync()
    {
        if (!CanBuild || _savedProfilePath is null)
        {
            return;
        }

        _buildCts?.Cancel();
        _buildCts?.Dispose();
        _buildCts = new CancellationTokenSource();
        CancellationToken ct = _buildCts.Token;

        IsBusy = true;
        BuildStatus = "Building… (approve UAC if prompted)";
        Status = BuildStatus;
        StatusIsError = false;
        OutputIsoPath = null;

        if (!WizardSession.TryParseLane(ImageQuality, out ImageQualityLane lane, out string? laneError))
        {
            BuildStatus = laneError ?? "Invalid image quality.";
            Status = BuildStatus;
            StatusIsError = true;
            IsBusy = false;
            return;
        }

        string work = WizardBuild.ResolveWorkDirectory(lane);
        WizardBuildInput input = new(
            _savedProfilePath,
            SourceIsoPath.Trim(),
            ImageQuality,
            WorkDirectory: null,
            WimIndex: _wimIndex);

        using CancellationTokenSource pollCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        Task pollTask = PollApplyStatusAsync(ApplyStatusReader.StatusPath(work), pollCts.Token);
        WizardBuildResult result;
        try
        {
            result = await WizardBuild.TryApplyAsync(input, cancellationToken: ct)
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
                // expected when Apply finishes or Cancel is pressed
            }
        }

        IsBusy = false;
        if (ct.IsCancellationRequested && !result.Succeeded)
        {
            BuildStatus = "Build cancelled.";
            Status = BuildStatus;
            StatusIsError = true;
            return;
        }

        // Finalize honestly — do not leave a mid-stage / done label after exit.
        BuildStatus = result.Message;
        Status = result.Message;
        StatusIsError = !result.Succeeded;
        if (result.Succeeded)
        {
            OutputIsoPath = result.OutputIsoPath;
            SaveStatus = $"Saved → {_savedProfilePath}\n{result.Message}";
        }
    }

    private async Task PollApplyStatusAsync(string statusPath, CancellationToken ct)
    {
        string? last = null;
        while (!ct.IsCancellationRequested)
        {
            try
            {
                string? label = ApplyStatusReader.FormatBusyLabel(
                    ApplyStatusReader.TryRead(statusPath, ct));
                if (label is not null && !string.Equals(label, last, StringComparison.Ordinal))
                {
                    last = label;
                    BuildStatus = label;
                    Status = label;
                    StatusIsError = label.StartsWith("Failed:", StringComparison.Ordinal);
                }

                await Task.Delay(500, ct).ConfigureAwait(true);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    [RelayCommand]
    private void CancelBuild() => _buildCts?.Cancel();

    [RelayCommand] private void Close() => _window.Close();

    private void RefreshCanBuild() =>
        CanBuild = WizardStageGates.CanBuild(
            SourceIsoReady(),
            IdentityReadyNow(),
            !string.IsNullOrEmpty(_savedProfilePath),
            IsBusy);

    private void RefreshNav()
    {
        bool sourceReady = SourceIsoReady();
        bool identityReady = IdentityReadyNow();
        CanGoBack = !IsBusy && StepIndex > WizardStageGates.Source;
        CanGoNext = !IsBusy
            && StepIndex < WizardStageGates.Review
            && WizardStageGates.CanAdvance(StepIndex, sourceReady, identityReady);
        NextLabel = "Continue";
        if (StepIndex == WizardStageGates.Review)
        {
            NextLabel = "Finish";
            CanGoNext = false;
        }

        StageLabel = StepNames[StepIndex];
        ProgressFraction = (StepIndex + 1) / (double)StepNames.Length;
        OnPropertyChanged(nameof(IsSourceStep));
        OnPropertyChanged(nameof(IsAccountStep));
        OnPropertyChanged(nameof(IsSoftwareStep));
        OnPropertyChanged(nameof(IsReviewStep));

        CanGoToSource = !IsBusy && WizardStageGates.CanGoTo(WizardStageGates.Source, sourceReady, identityReady);
        CanGoToAccount = !IsBusy && WizardStageGates.CanGoTo(WizardStageGates.Account, sourceReady, identityReady);
        CanGoToSoftware = !IsBusy && WizardStageGates.CanGoTo(WizardStageGates.Software, sourceReady, identityReady);
        CanGoToReview = !IsBusy && WizardStageGates.CanGoTo(WizardStageGates.Review, sourceReady, identityReady);
    }

    private bool SourceIsoReady() => WizardStageGates.SourceReady(SourceIsoPath);

    private bool IdentityReadyNow() => WizardStageGates.IdentityReady(Username, Password);

    private async Task ProbeSourceWimAsync()
    {
        int generation = ++_probeGeneration;
        _probeCts?.Cancel();
        _probeCts?.Dispose();
        _probeCts = new CancellationTokenSource();
        CancellationToken ct = _probeCts.Token;

        WimIndexes.Clear();
        SelectedWimIndex = null;
        IsWimPickerVisible = false;

        if (!SourceIsoReady())
        {
            IsWimProbeBusy = false;
            return;
        }

        IsWimProbeBusy = true;
        string path = SourceIsoPath.Trim();
        IWimIndexSource? source = _wimIndexSource;
        Result<IReadOnlyList<WimIndexInfo>, Failure> result =
            await SourceWimProbe.TryProbeIsoAsync(path, source, ct).ConfigureAwait(true);

        if (generation != _probeGeneration || ct.IsCancellationRequested)
        {
            return;
        }

        IsWimProbeBusy = false;
        if (!result.IsOk)
        {
            // Fail open on probe UX — reset to host default so Save/Build still work.
            _userChoseWimIndex = false;
            _wimIndex = _hostWimDefault;
            Status = $"{result.Error.Code}: {result.Error.Message}";
            StatusIsError = true;
            RefreshRecipe();
            return;
        }

        foreach (WimIndexInfo row in result.Value)
        {
            WimIndexes.Add(row);
        }

        int selected = SourceWimProbe.ResolveSelection(
            result.Value,
            _wimIndex,
            _userChoseWimIndex,
            _hostWimDefault);
        _wimIndex = selected;
        SelectedWimIndex = WimIndexes.FirstOrDefault(r => r.Index == selected);
        IsWimPickerVisible = true;
        if (StatusIsError && Status.StartsWith("wim.probe.", StringComparison.Ordinal))
        {
            Status = "";
            StatusIsError = false;
        }

        RefreshRecipe();
    }

    private bool RunPlan()
    {
        WizardSessionResult result = WizardSession.ComposeAndPlan(BuildInput());
        Status = result.Message;
        StatusIsError = !result.Succeeded;
        if (!result.Succeeded)
        {
            _lastProfileUtf8 = null;
            _lastArtifacts = null;
            _lastProfile = null;
            PreviewJson = "";
            PlanSummary = result.Message;
            FullPlanText = "";
            return false;
        }

        _lastProfileUtf8 = result.ProfileUtf8;
        _lastRequiresNetwork = result.RequiresNetwork;
        _lastArtifacts = result.Artifacts;
        PreviewJson = result.ProfileJson ?? "";
        PlanSummary = result.Message;
        if (_lastProfileUtf8 is not null)
        {
            Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile(_lastProfileUtf8);
            _lastProfile = parsed.IsOk ? parsed.Value : null;
        }

        RefreshReceipt();
        return true;
    }

    /// <summary>Review receipt — quiet labels from ProductPosture; What's included from Plan-effective AppX.</summary>
    private void RefreshReceipt()
    {
        QuietBlockText = IncludedReceipt.FormatQuietBlock(IsBraveSelected());
        PickStripText = IncludedReceipt.FormatPickStrip(SelectedPickLabels());
        PlanMetaText =
            $"Account {Username.Trim()} · region {Locale} / {TimeZone} · network {(_lastRequiresNetwork ? "needed" : "not needed")} · DMA {(DmaEnabled ? "on" : "off")} · {ImageQuality} lane";

        if (_lastArtifacts is not null && _lastProfile is not null)
        {
            FullPlanText = PlanDiff.Format(_lastArtifacts, _lastProfile);
            WhatsIncludedText = IsRecommendedPreset
                ? IncludedReceipt.FormatWhatsIncluded(_lastArtifacts.RemoveProvisionedAppx)
                : string.Empty;
            QuietSummaryText = IncludedReceipt.FormatQuietSummary(_lastArtifacts.RemoveProvisionedAppx.Count);
            return;
        }

        Result<DebloatExpansion, Failure> expanded = DebloatPresets.TryExpand(Preset);
        if (!expanded.IsOk)
        {
            return;
        }

        IReadOnlyList<string> effectiveAppx = ProductPosture.UnionAppx(expanded.Value.RemoveProvisionedAppx);
        WhatsIncludedText = IsRecommendedPreset
            ? IncludedReceipt.FormatWhatsIncluded(effectiveAppx)
            : string.Empty;
        QuietSummaryText = IncludedReceipt.FormatQuietSummary(effectiveAppx.Count);
        FullPlanText = "";
    }

    private bool IsBraveSelected() =>
        BrowserChips.Any(static c => c.Id == "brave" && c.IsSelected) ||
        IdList.FromMultiline(AdvancedWingetText)
            .Any(static id => string.Equals(id, ProductPosture.BraveWingetId, StringComparison.OrdinalIgnoreCase));

    private IEnumerable<string> SelectedPickLabels() =>
        SelectedLabels(BrowserChips)
            .Concat(SelectedLabels(EditorChips))
            .Concat(SelectedLabels(ShellChips))
            .Concat(SelectedLabels(WslChips));

    private static IEnumerable<string> SelectedLabels(ObservableCollection<ChipItem> chips) =>
        chips.Where(static c => c.IsEnabled && c.IsSelected).Select(static c => c.Label);

    private void RefreshRecipe()
    {
        string profilePath = _savedProfilePath ?? @"C:\path\to\winmint.profile.json";
        BuildRecipe = WizardSession.FormatBuildRecipe(profilePath, SourceIsoPath, ImageQuality, _wimIndex);
    }

    private WizardSessionInput BuildInput()
    {
        Result<PackageSelection, Failure> packagesResult = WizardSession.ResolvePackageChips(
            SelectedIds(BrowserChips),
            SelectedIds(EditorChips),
            SelectedIds(ShellChips),
            SelectedIds(WslChips));
        if (!packagesResult.IsOk)
        {
            throw new InvalidOperationException(
                $"{packagesResult.Error.Code}: {packagesResult.Error.Message}");
        }

        PackageSelection packages = packagesResult.Value;

        return new WizardSessionInput(
            Preset,
            Username,
            Password,
            RequireWifi,
            DmaEnabled,
            Locale,
            GeoId,
            TimeZone,
            LocationServices,
            WingetText: ProductPosture.StripWingetFromAuthored(
                WizardSession.MergeChipAndAdvanced(packages.WingetInstallIds, AdvancedWingetText)),
            ScoopText: ProductPosture.StripScoopFromAuthored(
                WizardSession.MergeChipAndAdvanced(packages.ScoopInstallIds, AdvancedScoopText)),
            WslText: WizardSession.MergeChipAndAdvanced(packages.WslProfileTokens, AdvancedWslText),
            SourceIsoPath: SourceIsoPath,
            ImageQualityText: ImageQuality,
            WimIndex: _wimIndex);
    }

    private static IEnumerable<string> SelectedIds(ObservableCollection<ChipItem> chips) =>
        chips.Where(static c => c.IsEnabled && c.IsSelected).Select(static c => c.Id);

    private static ObservableCollection<ChipItem> ToChips((string Id, string Label)[] items)
    {
        ObservableCollection<ChipItem> chips = [];
        foreach ((string id, string label) in items)
        {
            chips.Add(new ChipItem(id, label));
        }

        return chips;
    }

    public void Dispose()
    {
        _buildCts?.Cancel();
        _buildCts?.Dispose();
        _buildCts = null;
        _probeCts?.Cancel();
        _probeCts?.Dispose();
        _probeCts = null;
    }
}
