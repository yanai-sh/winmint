using CommunityToolkit.Mvvm.ComponentModel;

namespace WinMint.Wizard.ViewModels;

public sealed partial class ChipItem : ObservableObject
{
    public ChipItem(string id, string label, bool isSelected = false)
    {
        Id = id;
        Label = label;
        _isSelected = isSelected;
    }

    public string Id { get; }
    public string Label { get; }

    [ObservableProperty]
    private bool _isSelected;
}
