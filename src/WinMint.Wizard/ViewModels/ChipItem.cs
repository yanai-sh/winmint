using CommunityToolkit.Mvvm.ComponentModel;

namespace WinMint.Wizard.ViewModels;

public sealed partial class ChipItem : ObservableObject
{
    public ChipItem(
        string id,
        string label,
        bool isSelected = false,
        bool isEnabled = true,
        string? toolTip = null)
    {
        Id = id;
        Label = label;
        _isSelected = isSelected;
        IsEnabled = isEnabled;
        ToolTip = toolTip;
    }

    public string Id { get; }
    public string Label { get; }
    public bool IsEnabled { get; }
    public string? ToolTip { get; }

    [ObservableProperty]
    private bool _isSelected;
}
