using System.Collections.ObjectModel;
using Avalonia.Controls;
using Avalonia.Platform.Storage;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WinMint.Orchestrator;

namespace WinMint.Wizard.ViewModels;

/// <summary>v1-shaped host shell — curated chips, silent account/DMA defaults, no catalog dump.</summary>
public sealed partial class WizardShellViewModel : ObservableObject, IDisposable
{
    private static readonly string[] StepNames = ["Media", "You", "Taste", "Included"];

    private readonly Window _window;
    private readonly int _hostWimDefault = HostEdition.DefaultWimIndex();
    private readonly IWimIndexSource? _wimIndexSource;
    private byte[]? _lastProfileUtf8;
    private bool _lastRequiresNetwork;
    private string? _savedProfilePath;
    private CancellationTokenSource? _buildCts;
    private CancellationTokenSource? _probeCts;
    private int _wimIndex;
    private bool _userChoseWimIndex;
    private int _probeGeneration;

    public WizardShellViewModel(Window window)
        : this(window, wimIndexSource: null)
    {
    }

    internal WizardShellViewModel(Window window, IWimIndexSource? wimIndexSource)
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
        ShellChips = ToChips(
        [
            ("windhawk", "Windhawk"),
            ("yasb", "YASB"),
            ("komorebi", "Komorebi"),
            ("nilesoft", "Nilesoft"),
        ]);
        foreach (ChipItem chip in ShellChips)
        {
            chip.IsSelected = chip.Id is "windhawk" or "yasb" or "komorebi";
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
    [ObservableProperty] private string _stageLabel = "Media";
    [ObservableProperty] private double _progressFraction = 0.25;
    [ObservableProperty] private bool _canGoBack;
    [ObservableProperty] private bool _canGoNext = true;
    [ObservableProperty] private string _nextLabel = "Continue";
    [ObservableProperty] private bool _canGoToMedia = true;
    [ObservableProperty] private bool _canGoToYou;
    [ObservableProperty] private bool _canGoToTaste;
    [ObservableProperty] private bool _canGoToIncluded;

    [ObservableProperty] private string _sourceIsoPath = "";
    [ObservableProperty] private string _imageQuality = "Test";
    [ObservableProperty] private string _preset = KeepFlagPresets.Recommended;
    [ObservableProperty] private bool _keepGaming;
    [ObservableProperty] private bool _keepCopilot;

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

    // Included receipt layers (ADR-009 quiet block, pick strip, collapsed remove-list, plan meta).
    [ObservableProperty] private string _quietSummaryText = "";
    [ObservableProperty] private string _pickStripText = "";
    [ObservableProperty] private string _quietBlockText = "";
    [ObservableProperty] private string _whatsIncludedText = "";
    [ObservableProperty] private string _planMetaText = "";
    [ObservableProperty] private string _saveStatus = "";
    [ObservableProperty] private bool _canBuild;
    [ObservableProperty] private bool _isBusy;
    [ObservableProperty] private string _buildStatus = "";
    [ObservableProperty] private string? _outputIsoPath;

    public bool IsMediaStep => StepIndex == WizardStageGates.Media;
    public bool IsYouStep => StepIndex == WizardStageGates.You;
    public bool IsTasteStep => StepIndex == WizardStageGates.Taste;
    public bool IsIncludedStep => StepIndex == WizardStageGates.Included;

    public bool IsEmptyPreset => string.Equals(Preset, KeepFlagPresets.Empty, StringComparison.OrdinalIgnoreCase);
    public bool IsAcceptancePreset => string.Equals(Preset, KeepFlagPresets.Acceptance, StringComparison.OrdinalIgnoreCase);
    public bool IsRecommendedPreset => string.Equals(Preset, KeepFlagPresets.Recommended, StringComparison.OrdinalIgnoreCase);
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

    [RelayCommand] private void SelectEmptyPreset() => Preset = KeepFlagPresets.Empty;
    [RelayCommand] private void SelectAcceptancePreset() => Preset = KeepFlagPresets.Acceptance;
    [RelayCommand] private void SelectRecommendedPreset() => Preset = KeepFlagPresets.Recommended;

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
        });

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
        if (StepIndex > WizardStageGates.Media)
        {
            StepIndex--;
        }
    }

    [RelayCommand]
    private void Next()
    {
        if (StepIndex >= WizardStageGates.Included)
        {
            return;
        }

        if (!WizardStageGates.CanAdvance(StepIndex, SourceIsoReady(), IdentityReadyNow()))
        {
            Status = StepIndex == WizardStageGates.Taste
                ? "Add a password on You to continue."
                : "Choose an existing Source ISO to continue.";
            StatusIsError = true;
            return;
        }

        if (StepIndex == WizardStageGates.Taste)
        {
            TryEnterIncluded();
            return;
        }

        StepIndex++;
    }

    // Stage scrub — status-bar Media/You/Taste/Included labels jump directly via WizardStageGates.CanGoTo.
    [RelayCommand] private void GoToMedia() => GoToStage(WizardStageGates.Media);
    [RelayCommand] private void GoToYou() => GoToStage(WizardStageGates.You);
    [RelayCommand] private void GoToTaste() => GoToStage(WizardStageGates.Taste);
    [RelayCommand] private void GoToIncluded() => GoToStage(WizardStageGates.Included);

    private void GoToStage(int targetIndex)
    {
        if (targetIndex == StepIndex)
        {
            return;
        }

        if (!WizardStageGates.CanGoTo(targetIndex, SourceIsoReady(), IdentityReadyNow()))
        {
            Status = targetIndex == WizardStageGates.Included
                ? "Add a password on You to continue."
                : "Choose an existing Source ISO to continue.";
            StatusIsError = true;
            return;
        }

        if (targetIndex == WizardStageGates.Included)
        {
            // Jumping straight to Included composes the receipt, same as Next from Taste.
            TryEnterIncluded();
            return;
        }

        StepIndex = targetIndex;
    }

    /// <summary>Taste skip — host `recommended` + product defaults, keeps/packages untouched (spec §Taste skip).</summary>
    [RelayCommand]
    private void UseDefaults()
    {
        Preset = KeepFlagPresets.Recommended;
        if (!WizardStageGates.CanGoTo(WizardStageGates.Included, SourceIsoReady(), IdentityReadyNow()))
        {
            StepIndex = WizardStageGates.You;
            Status = "Add a password on You to continue.";
            StatusIsError = true;
            return;
        }

        TryEnterIncluded();
    }

    private bool TryEnterIncluded()
    {
        if (!RunPlan())
        {
            return false;
        }

        StepIndex = WizardStageGates.Included;
        RefreshRecipe();
        return true;
    }

    [RelayCommand]
    private void Replan() => RunPlan();

    [RelayCommand]
    private async Task SaveProfileAsync()
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
        });

        if (file is null)
        {
            return;
        }

        string? path = file.TryGetLocalPath();
        if (string.IsNullOrEmpty(path))
        {
            Status = "Save failed: could not resolve local path.";
            StatusIsError = true;
            return;
        }

        await File.WriteAllBytesAsync(path, _lastProfileUtf8);
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

        string work = WizardBuild.DefaultWorkDirectory;
        WizardBuildInput input = new(
            _savedProfilePath,
            SourceIsoPath.Trim(),
            ImageQuality,
            WorkDirectory: work,
            WimIndex: _wimIndex);

        using CancellationTokenSource pollCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        Task pollTask = PollApplyStatusAsync(ApplyStatusReader.StatusPath(work), pollCts.Token);
        WizardBuildResult result;
        try
        {
            result = await Task.Run(() => WizardBuild.TryApply(input, cancellationToken: ct), ct)
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
        CanGoBack = !IsBusy && StepIndex > WizardStageGates.Media;
        CanGoNext = !IsBusy
            && StepIndex < WizardStageGates.Included
            && WizardStageGates.CanAdvance(StepIndex, sourceReady, identityReady);
        NextLabel = "Continue";
        if (StepIndex == WizardStageGates.Included)
        {
            NextLabel = "Finish";
            CanGoNext = false;
        }

        StageLabel = StepNames[StepIndex];
        ProgressFraction = (StepIndex + 1) / (double)StepNames.Length;
        OnPropertyChanged(nameof(IsMediaStep));
        OnPropertyChanged(nameof(IsYouStep));
        OnPropertyChanged(nameof(IsTasteStep));
        OnPropertyChanged(nameof(IsIncludedStep));

        CanGoToMedia = !IsBusy && WizardStageGates.CanGoTo(WizardStageGates.Media, sourceReady, identityReady);
        CanGoToYou = !IsBusy && WizardStageGates.CanGoTo(WizardStageGates.You, sourceReady, identityReady);
        CanGoToTaste = !IsBusy && WizardStageGates.CanGoTo(WizardStageGates.Taste, sourceReady, identityReady);
        CanGoToIncluded = !IsBusy && WizardStageGates.CanGoTo(WizardStageGates.Included, sourceReady, identityReady);
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
        Result<IReadOnlyList<WimIndexInfo>, WimProbeFailure> result = await Task.Run(
                () => SourceWimProbe.TryProbeIso(path, source, ct), ct)
            .ConfigureAwait(true);

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
            PreviewJson = "";
            PlanSummary = result.Message;
            return false;
        }

        _lastProfileUtf8 = result.ProfileUtf8;
        _lastRequiresNetwork = result.RequiresNetwork;
        PreviewJson = result.ProfileJson ?? "";
        PlanSummary = result.Message;
        RefreshReceipt();
        return true;
    }

    /// <summary>Included receipt text layers — quiet block is ADR-009 constants only; What's included is the `recommended` remove-list.</summary>
    private void RefreshReceipt()
    {
        QuietBlockText = IncludedReceipt.FormatQuietBlock(KeepCopilot, IsBraveSelected());
        PickStripText = IncludedReceipt.FormatPickStrip(SelectedPickLabels());
        PlanMetaText =
            $"requiresNetwork {(_lastRequiresNetwork ? "yes" : "no")} · DMA {(DmaEnabled ? "on" : "off")} · {ImageQuality} lane";

        Result<KeepFlagExpansion, PlanFailure> expanded = KeepFlagPresets.TryExpand(Preset, KeepGaming, KeepCopilot);
        if (!expanded.IsOk)
        {
            return;
        }

        WhatsIncludedText = IsRecommendedPreset
            ? IncludedReceipt.FormatWhatsIncluded(expanded.Value.RemoveProvisionedAppx)
            : string.Empty;
        QuietSummaryText = IncludedReceipt.FormatQuietSummary(
            expanded.Value.RemoveProvisionedAppx.Count,
            KeepCopilot,
            KeepGaming);
    }

    private bool IsBraveSelected() =>
        BrowserChips.Any(static c => c.Id == "brave" && c.IsSelected) ||
        AdvancedWingetText
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .Any(static line => line.Trim().Equals("Brave.Brave", StringComparison.OrdinalIgnoreCase));

    private IEnumerable<string> SelectedPickLabels()
    {
        if (KeepGaming)
        {
            yield return "Xbox & gaming";
        }

        if (KeepCopilot)
        {
            yield return "Copilot";
        }

        foreach (string label in SelectedLabels(BrowserChips)
            .Concat(SelectedLabels(EditorChips))
            .Concat(SelectedLabels(ShellChips))
            .Concat(SelectedLabels(WslChips)))
        {
            yield return label;
        }
    }

    private static IEnumerable<string> SelectedLabels(ObservableCollection<ChipItem> chips) =>
        chips.Where(static c => c.IsSelected).Select(static c => c.Label);

    private void RefreshRecipe()
    {
        string profilePath = _savedProfilePath ?? @"C:\path\to\winmint.profile.json";
        BuildRecipe = WizardSession.FormatBuildRecipe(profilePath, SourceIsoPath, ImageQuality, _wimIndex);
    }

    private WizardSessionInput BuildInput()
    {
        PackageSelection packages = WizardSession.ResolvePackageChips(
            SelectedIds(BrowserChips),
            SelectedIds(EditorChips),
            SelectedIds(ShellChips),
            SelectedIds(WslChips));

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
            KeepGaming: KeepGaming,
            KeepCopilot: KeepCopilot,
            WingetText: WizardSession.MergeChipAndAdvanced(packages.WingetInstallIds, AdvancedWingetText),
            ScoopText: WizardSession.MergeChipAndAdvanced(packages.ScoopInstallIds, AdvancedScoopText),
            WslText: WizardSession.MergeChipAndAdvanced(packages.WslProfileTokens, AdvancedWslText),
            SourceIsoPath: SourceIsoPath,
            ImageQualityText: ImageQuality,
            WimIndex: _wimIndex);
    }

    private static IEnumerable<string> SelectedIds(ObservableCollection<ChipItem> chips) =>
        chips.Where(static c => c.IsSelected).Select(static c => c.Id);

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
