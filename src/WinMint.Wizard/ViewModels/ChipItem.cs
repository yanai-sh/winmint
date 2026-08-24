using CommunityToolkit.Mvvm.ComponentModel;

namespace WinMint.Wizard.ViewModels;

public sealed partial class ChipItem(
    string id,
    string label,
    bool isSelected = false,
    bool isEnabled = true,
    string? toolTip = null) : ObservableObject
{
    public string Id { get; } = id;
    public string Label { get; } = label;
    public bool IsEnabled { get; } = isEnabled;
    public string? ToolTip { get; } = toolTip;

    public string Glyph
    {
        get
        {
            string compact = Label.Replace(" ", "", StringComparison.Ordinal);
            return compact.Length >= 2 ? compact[..2] : compact;
        }
    }

    [ObservableProperty]
    private bool _isSelected = isSelected;
}
