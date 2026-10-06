using System.Collections.ObjectModel;

using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

using WinMint.Orchestrator;

namespace WinMint.Wizard.ViewModels;

public interface ISoftwareStageViewModel
{
    CuratedChipSelection Chips { get; }
    DesktopSelectionViewModel Desktop { get; }
    StationOutcomeSelectionViewModel Outcomes { get; }
    AdvancedPackageTextViewModel Advanced { get; }
    IAsyncRelayCommand UseDefaultsCommand { get; }
    StageStatusViewModel Status { get; }
}

public sealed partial class DesktopSelectionViewModel : ObservableObject
{
    private readonly Action _changed;
    [ObservableProperty] private string _taskbar = StationOutcomes.TaskbarWindows;
    [ObservableProperty] private bool _komorebi;

    internal DesktopSelectionViewModel(Action changed) => _changed = changed;

    public bool IsWindowsTaskbar => string.Equals(Taskbar, StationOutcomes.TaskbarWindows, StringComparison.Ordinal);
    public bool IsYasbTaskbar => string.Equals(Taskbar, StationOutcomes.TaskbarYasb, StringComparison.Ordinal);

    partial void OnTaskbarChanged(string value)
    {
        OnPropertyChanged(nameof(IsWindowsTaskbar));
        OnPropertyChanged(nameof(IsYasbTaskbar));
        _changed();
    }

    partial void OnKomorebiChanged(bool value) => _changed();

    [RelayCommand]
    private void SelectTaskbar(string? taskbar)
    {
        if (string.Equals(taskbar, StationOutcomes.TaskbarWindows, StringComparison.Ordinal)
            || string.Equals(taskbar, StationOutcomes.TaskbarYasb, StringComparison.Ordinal))
        {
            Taskbar = taskbar!;
        }
    }
}

public sealed class CuratedChipSelection
{
    internal CuratedChipSelection(Action changed)
    {
        Browsers = Create(CuratedPackageChips.Browsers, changed);
        Editors = Create(CuratedPackageChips.Editors, changed);
        Wsl = Create(CuratedPackageChips.Wsl, changed);
    }

    public ObservableCollection<ChipItem> Browsers { get; }
    public ObservableCollection<ChipItem> Editors { get; }
    public ObservableCollection<ChipItem> Wsl { get; }

    internal IEnumerable<ChipItem> All => Browsers.Concat(Editors).Concat(Wsl);

    private static ObservableCollection<ChipItem> Create(
        IReadOnlyList<CuratedChipDefinition> definitions,
        Action changed)
    {
        ObservableCollection<ChipItem> chips = [];
        foreach (CuratedChipDefinition definition in definitions)
        {
            ChipItem chip = new(
                definition.Key,
                definition.Label,
                isEnabled: definition.IsEnabled,
                toolTip: definition.ToolTip);
            chip.PropertyChanged += (_, _) => changed();
            chips.Add(chip);
        }
        return chips;
    }
}

public sealed partial class StationOutcomeSelectionViewModel : ObservableObject
{
    private readonly Action _changed;
    private readonly Action<string> _apply;
    [ObservableProperty] private string _value = StationOutcomes.Comfort;

    internal StationOutcomeSelectionViewModel(Action changed, Action<string> apply)
    {
        _changed = changed;
        _apply = apply;
    }

    public bool IsMinimal => string.Equals(Value, StationOutcomes.Minimal, StringComparison.OrdinalIgnoreCase);
    public bool IsComfort => string.Equals(Value, StationOutcomes.Comfort, StringComparison.OrdinalIgnoreCase);
    public bool IsPower => string.Equals(Value, StationOutcomes.Power, StringComparison.OrdinalIgnoreCase);

    partial void OnValueChanged(string value)
    {
        OnPropertyChanged(nameof(IsMinimal));
        OnPropertyChanged(nameof(IsComfort));
        OnPropertyChanged(nameof(IsPower));
        _changed();
    }

    [RelayCommand]
    private void Select(string? outcome)
    {
        if (!string.IsNullOrWhiteSpace(outcome))
        {
            _apply(outcome.Trim());
        }
    }
}

public sealed partial class AdvancedPackageTextViewModel : ObservableObject
{
    private readonly Action _changed;
    internal AdvancedPackageTextViewModel(Action changed) => _changed = changed;

    [ObservableProperty] private string _winget = "";
    [ObservableProperty] private string _scoop = "";
    [ObservableProperty] private string _wsl = "";

    partial void OnWingetChanged(string value) => _changed();
    partial void OnScoopChanged(string value) => _changed();
    partial void OnWslChanged(string value) => _changed();
}

internal sealed partial class SoftwareStageViewModel : ObservableObject, ISoftwareStageViewModel
{
    private readonly Func<Task> _useDefaults;

    public SoftwareStageViewModel(Action draftChanged, Func<Task> useDefaults)
    {
        _useDefaults = useDefaults;
        Chips = new CuratedChipSelection(draftChanged);
        Desktop = new DesktopSelectionViewModel(draftChanged);
        Advanced = new AdvancedPackageTextViewModel(draftChanged);
        Status = new StageStatusViewModel();
        Outcomes = new StationOutcomeSelectionViewModel(draftChanged, ApplyStationOutcome);
    }

    public CuratedChipSelection Chips { get; }
    public DesktopSelectionViewModel Desktop { get; }
    public StationOutcomeSelectionViewModel Outcomes { get; }
    public AdvancedPackageTextViewModel Advanced { get; }
    public StageStatusViewModel Status { get; }

    [RelayCommand]
    private Task UseDefaults() => _useDefaults();

    /// <summary>Comfort Station outcome seed (issue #136 / #140).</summary>
    internal void ApplyCuratedDefaults() => ApplyStationOutcome(StationOutcomes.Comfort);

    internal void ApplyStationOutcome(string outcome)
    {
        Result<StationSeed, Failure> seed = StationOutcomes.TrySeed(outcome);
        if (!seed.IsOk)
        {
            return;
        }

        string normalized = outcome.Trim().ToLowerInvariant() switch
        {
            StationOutcomes.Minimal => StationOutcomes.Minimal,
            StationOutcomes.Power => StationOutcomes.Power,
            _ => StationOutcomes.Comfort,
        };
        Outcomes.Value = normalized;

        HashSet<string> selected = new(
            seed.Value.ToolChipKeys.Concat(seed.Value.WslTokens),
            StringComparer.OrdinalIgnoreCase);
        foreach (ChipItem chip in Chips.All)
        {
            chip.IsSelected = selected.Contains(chip.Id);
        }

        Desktop.Taskbar = string.Equals(
            seed.Value.TaskbarSurface,
            StationOutcomes.TaskbarYasb,
            StringComparison.Ordinal)
            ? StationOutcomes.TaskbarYasb
            : StationOutcomes.TaskbarWindows;
        Desktop.Komorebi = seed.Value.Komorebi;
        Advanced.Winget = "";
        Advanced.Scoop = "";
        Advanced.Wsl = "";
    }

    internal IReadOnlyList<string> SelectedToolChipKeys() =>
        [.. SelectedIds(Chips.Browsers).Concat(SelectedIds(Chips.Editors))];

    internal IReadOnlyList<string> SelectedWslTokens() => [.. SelectedIds(Chips.Wsl)];

    internal string TaskbarSurfaceForCompile =>
        Desktop.IsYasbTaskbar ? StationOutcomes.TaskbarYasb : StationOutcomes.TaskbarWindows;

    private static IEnumerable<string> SelectedIds(IEnumerable<ChipItem> chips) =>
        chips.Where(static chip => chip.IsEnabled && chip.IsSelected).Select(static chip => chip.Id);
}
