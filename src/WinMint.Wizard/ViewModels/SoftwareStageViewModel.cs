using System.Collections.ObjectModel;

using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

using WinMint.Orchestrator;

namespace WinMint.Wizard.ViewModels;

public interface ISoftwareStageViewModel
{
    CuratedChipSelection Chips { get; }
    PresetSelectionViewModel Presets { get; }
    AdvancedPackageTextViewModel Advanced { get; }
    IAsyncRelayCommand UseDefaultsCommand { get; }
    StageStatusViewModel Status { get; }
}

public sealed class CuratedChipSelection
{
    internal CuratedChipSelection(Action changed)
    {
        Browsers = Create(CuratedPackageChips.Browsers, changed);
        Editors = Create(CuratedPackageChips.Editors, changed);
        Shells = Create(CuratedPackageChips.Shells, changed);
        Wsl = Create(CuratedPackageChips.Wsl, changed);
    }

    public ObservableCollection<ChipItem> Browsers { get; }
    public ObservableCollection<ChipItem> Editors { get; }
    public ObservableCollection<ChipItem> Shells { get; }
    public ObservableCollection<ChipItem> Wsl { get; }

    internal IEnumerable<ChipItem> All => Browsers.Concat(Editors).Concat(Shells).Concat(Wsl);

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

public sealed partial class PresetSelectionViewModel : ObservableObject
{
    private readonly Action _changed;
    [ObservableProperty] private string _value = DebloatPresets.Recommended;

    internal PresetSelectionViewModel(Action changed) => _changed = changed;

    public bool IsEmpty => string.Equals(Value, DebloatPresets.Empty, StringComparison.OrdinalIgnoreCase);
    public bool IsAcceptance => string.Equals(Value, DebloatPresets.Acceptance, StringComparison.OrdinalIgnoreCase);
    public bool IsRecommended => string.Equals(Value, DebloatPresets.Recommended, StringComparison.OrdinalIgnoreCase);

    partial void OnValueChanged(string value)
    {
        OnPropertyChanged(nameof(IsEmpty));
        OnPropertyChanged(nameof(IsAcceptance));
        OnPropertyChanged(nameof(IsRecommended));
        _changed();
    }

    [RelayCommand]
    private void Select(string? preset)
    {
        if (!string.IsNullOrWhiteSpace(preset))
        {
            Value = preset;
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

internal sealed partial class SoftwareStageViewModel(Action draftChanged, Func<Task> useDefaults) : ObservableObject, ISoftwareStageViewModel
{
    private readonly Func<Task> _useDefaults = useDefaults;

    public CuratedChipSelection Chips { get; } = new CuratedChipSelection(draftChanged);
    public PresetSelectionViewModel Presets { get; } = new PresetSelectionViewModel(draftChanged);
    public AdvancedPackageTextViewModel Advanced { get; } = new AdvancedPackageTextViewModel(draftChanged);
    public StageStatusViewModel Status { get; } = new();

    [RelayCommand]
    private Task UseDefaults() => _useDefaults();

    internal void ResetToDefaults()
    {
        Presets.Value = DebloatPresets.Recommended;
        foreach (ChipItem chip in Chips.All)
        {
            chip.IsSelected = false;
        }
        Advanced.Winget = "";
        Advanced.Scoop = "";
        Advanced.Wsl = "";
    }

    internal Result<PackageSelection, Failure> ResolvePackages()
    {
        PackageCatalog catalog = PackageCatalog.Default;
        IEnumerable<string> toolKeys = SelectedIds(Chips.Browsers)
            .Concat(SelectedIds(Chips.Editors))
            .Concat(SelectedIds(Chips.Shells))
            .Where(CuratedPackageChips.IsPackageTool);
        Result<PackageSelection, Failure> tools = catalog.ResolveToolKeys(toolKeys);
        if (!tools.IsOk)
        {
            return tools;
        }

        Result<IReadOnlyList<string>, Failure> wsl = catalog.ResolveWslTokens(SelectedIds(Chips.Wsl));
        return wsl.IsOk
            ? Result.Ok<PackageSelection, Failure>(
                new PackageSelection(tools.Value.WingetInstallIds, tools.Value.ScoopInstallIds, wsl.Value))
            : Result.Fail<PackageSelection, Failure>(wsl.Error);
    }

    internal IEnumerable<string> SelectedLabels() =>
        Chips.All.Where(static chip => chip.IsEnabled && chip.IsSelected).Select(static chip => chip.Label);

    private static IEnumerable<string> SelectedIds(IEnumerable<ChipItem> chips) =>
        chips.Where(static chip => chip.IsEnabled && chip.IsSelected).Select(static chip => chip.Id);
}
