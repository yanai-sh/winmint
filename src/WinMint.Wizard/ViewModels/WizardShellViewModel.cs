using System.Collections.ObjectModel;
using Avalonia.Controls;
using Avalonia.Platform.Storage;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WinMint.Orchestrator;

namespace WinMint.Wizard.ViewModels;

/// <summary>v1-shaped host shell — curated chips, silent account/DMA defaults, no catalog dump.</summary>
public sealed partial class WizardShellViewModel : ObservableObject
{
    private static readonly string[] StepNames = ["Source", "Configure", "Preview", "Review"];

    private static readonly string[] GamingAppx =
    [
        "Microsoft.GamingApp",
        "Microsoft.Xbox.TCUI",
        "Microsoft.XboxGamingOverlay",
        "Microsoft.XboxSpeechToTextOverlay",
    ];

    private readonly Window _window;
    private byte[]? _lastProfileUtf8;
    private string? _savedProfilePath;

    // Silent default from host SKU: Home unless Wizard host is Pro (not shown in Source UI).
    private readonly int? _wimIndex = HostEdition.DefaultWimIndex();

    public WizardShellViewModel(Window window)
    {
        _window = window;

        BrowserChips = ToChips(
        [
            ("zen-browser", "Zen"),
            ("Mozilla.Firefox.DeveloperEdition", "Firefox Dev"),
            ("Brave.Brave", "Brave"),
            ("Microsoft.Edge", "Edge"),
        ]);
        EditorChips = ToChips(
        [
            ("Anysphere.Cursor", "Cursor"),
            ("Microsoft.VisualStudioCode", "VS Code"),
            ("zedindustries.zed", "Zed"),
            ("Neovim.Neovim", "Neovim"),
        ]);
        ShellChips = ToChips(
        [
            ("windhawk", "Windhawk"),
            ("yasb", "YASB"),
            ("komorebi", "Komorebi"),
            ("nilesoft-shell", "Nilesoft"),
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
    [ObservableProperty] private string _preset = KeepFlagPresets.Acceptance;
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

    [ObservableProperty] private string _status = "";
    [ObservableProperty] private bool _statusIsError;
    [ObservableProperty] private string _previewJson = "";
    [ObservableProperty] private string _planSummary = "";
    [ObservableProperty] private string _buildRecipe = "";
    [ObservableProperty] private string _saveStatus = "";

    public bool IsSourceStep => StepIndex == 0;
    public bool IsConfigureStep => StepIndex == 1;
    public bool IsPreviewStep => StepIndex == 2;
    public bool IsReviewStep => StepIndex == 3;

    public bool IsEmptyPreset => string.Equals(Preset, KeepFlagPresets.Empty, StringComparison.OrdinalIgnoreCase);
    public bool IsAcceptancePreset => string.Equals(Preset, KeepFlagPresets.Acceptance, StringComparison.OrdinalIgnoreCase);
    public bool IsTestLane => string.Equals(ImageQuality, "Test", StringComparison.OrdinalIgnoreCase);
    public bool IsReleaseLane => string.Equals(ImageQuality, "Release", StringComparison.OrdinalIgnoreCase);

    partial void OnStepIndexChanged(int value) => RefreshNav();
    partial void OnSourceIsoPathChanged(string value) => RefreshNav();

    partial void OnPresetChanged(string value)
    {
        OnPropertyChanged(nameof(IsEmptyPreset));
        OnPropertyChanged(nameof(IsAcceptancePreset));
    }

    partial void OnImageQualityChanged(string value)
    {
        OnPropertyChanged(nameof(IsTestLane));
        OnPropertyChanged(nameof(IsReleaseLane));
    }

    [RelayCommand] private void SelectEmptyPreset() => Preset = KeepFlagPresets.Empty;
    [RelayCommand] private void SelectAcceptancePreset() => Preset = KeepFlagPresets.Acceptance;
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
    }

    [RelayCommand] private void Close() => _window.Close();

    private void RefreshNav()
    {
        CanGoBack = StepIndex > 0;
        CanGoNext = StepIndex < StepNames.Length - 1 && (StepIndex != 0 || SourceIsoReady());
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
        List<string> winget = SelectedIds(BrowserChips)
            .Concat(SelectedIds(EditorChips))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        List<string> scoop = SelectedIds(ShellChips).ToList();
        List<string> wsl = SelectedIds(WslChips).ToList();

        string appxOverride = "";
        if (IsAcceptancePreset && !KeepGaming)
        {
            Result<KeepFlagExpansion, PlanFailure> expanded = KeepFlagPresets.TryExpand(KeepFlagPresets.Acceptance);
            if (expanded.IsOk)
            {
                IEnumerable<string> merged = expanded.Value.RemoveProvisionedAppx
                    .Concat(GamingAppx)
                    .Distinct(StringComparer.OrdinalIgnoreCase);
                appxOverride = string.Join(Environment.NewLine, merged);
            }
        }

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
            WingetText: string.Join(Environment.NewLine, winget),
            ScoopText: string.Join(Environment.NewLine, scoop),
            WslText: string.Join(Environment.NewLine, wsl),
            RemoveProvisionedAppxText: appxOverride,
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
}
