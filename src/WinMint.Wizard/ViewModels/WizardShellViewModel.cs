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
    private static readonly string[] StepNames = ["Source", "Configure", "Preview", "Review"];

    private readonly Window _window;
    private byte[]? _lastProfileUtf8;
    private string? _savedProfilePath;
    private CancellationTokenSource? _buildCts;

    // Silent default from host SKU: Home unless Wizard host is Pro (not shown in Source UI).
    private readonly int? _wimIndex = HostEdition.DefaultWimIndex();

    public WizardShellViewModel(Window window)
    {
        _window = window;

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
    [ObservableProperty] private string _stageLabel = "Source";
    [ObservableProperty] private double _progressFraction = 0.25;
    [ObservableProperty] private bool _canGoBack;
    [ObservableProperty] private bool _canGoNext = true;
    [ObservableProperty] private string _nextLabel = "Continue";

    [ObservableProperty] private string _sourceIsoPath = "";
    [ObservableProperty] private string _imageQuality = "Test";
    [ObservableProperty] private string _preset = KeepFlagPresets.Recommended;
    [ObservableProperty] private bool _keepGaming;
    [ObservableProperty] private bool _keepCopilot;

    [ObservableProperty] private string _username = "winmint";
    [ObservableProperty] private string _password = "winmint";
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
    [ObservableProperty] private string _saveStatus = "";
    [ObservableProperty] private bool _canBuild;
    [ObservableProperty] private bool _isBusy;
    [ObservableProperty] private string _buildStatus = "";
    [ObservableProperty] private string? _outputIsoPath;

    public bool IsSourceStep => StepIndex == 0;
    public bool IsConfigureStep => StepIndex == 1;
    public bool IsPreviewStep => StepIndex == 2;
    public bool IsReviewStep => StepIndex == 3;

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
    }

    partial void OnIsBusyChanged(bool value)
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
                SourceIsoPath = path;
                Status = "";
                StatusIsError = false;
            }
        }
    }

    [RelayCommand]
    private void Back()
    {
        if (StepIndex > 0)
        {
            StepIndex--;
        }
    }

    [RelayCommand]
    private void Next()
    {
        if (StepIndex == 0 && !SourceIsoReady())
        {
            Status = "Choose an existing Source ISO to continue.";
            StatusIsError = true;
            return;
        }

        if (StepIndex == 1 && !RunPlan())
        {
            return;
        }

        if (StepIndex < StepNames.Length - 1)
        {
            StepIndex++;
            if (StepIndex == 3)
            {
                RefreshRecipe();
            }
        }
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

        WizardBuildInput input = new(
            _savedProfilePath,
            SourceIsoPath.Trim(),
            ImageQuality,
            WorkDirectory: WizardBuild.DefaultWorkDirectory,
            WimIndex: _wimIndex);

        WizardBuildResult result = await Task.Run(() => WizardBuild.TryApply(input, cancellationToken: ct), ct)
            .ConfigureAwait(true);

        IsBusy = false;
        if (ct.IsCancellationRequested && !result.Succeeded)
        {
            BuildStatus = "Build cancelled.";
            Status = BuildStatus;
            StatusIsError = true;
            return;
        }

        BuildStatus = result.Message;
        Status = result.Message;
        StatusIsError = !result.Succeeded;
        if (result.Succeeded)
        {
            OutputIsoPath = result.OutputIsoPath;
            SaveStatus = $"Saved → {_savedProfilePath}\n{result.Message}";
        }
    }

    [RelayCommand]
    private void CancelBuild() => _buildCts?.Cancel();

    [RelayCommand] private void Close() => _window.Close();

    private void RefreshCanBuild() =>
        CanBuild = !IsBusy
            && !string.IsNullOrEmpty(_savedProfilePath)
            && SourceIsoReady();

    private void RefreshNav()
    {
        CanGoBack = !IsBusy && StepIndex > 0;
        CanGoNext = !IsBusy && StepIndex < StepNames.Length - 1 && (StepIndex != 0 || SourceIsoReady());
        NextLabel = "Continue";
        if (StepIndex == StepNames.Length - 1)
        {
            NextLabel = "Finish";
            CanGoNext = false;
        }

        StageLabel = StepNames[StepIndex];
        ProgressFraction = (StepIndex + 1) / (double)StepNames.Length;
        OnPropertyChanged(nameof(IsSourceStep));
        OnPropertyChanged(nameof(IsConfigureStep));
        OnPropertyChanged(nameof(IsPreviewStep));
        OnPropertyChanged(nameof(IsReviewStep));
    }

    private bool SourceIsoReady() =>
        !string.IsNullOrWhiteSpace(SourceIsoPath) && File.Exists(SourceIsoPath.Trim());

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
        PreviewJson = result.ProfileJson ?? "";
        PlanSummary = result.Message;
        return true;
    }

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
    }
}
