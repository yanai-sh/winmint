using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Platform.Storage;

using WinMint.Wizard.ViewModels;

namespace WinMint.Wizard.Views;

public partial class SourceStepView : UserControl
{
    public SourceStepView()
    {
        InitializeComponent();
        AddHandler(DragDrop.DragOverEvent, OnDragOver);
        AddHandler(DragDrop.DragLeaveEvent, OnDragLeave);
        AddHandler(DragDrop.DropEvent, OnDrop);
    }

    private void OnDragOver(object? sender, DragEventArgs e)
    {
        bool offer = e.DataTransfer?.Contains(DataFormat.File) == true;
        e.DragEffects = offer ? DragDropEffects.Copy : DragDropEffects.None;
        SetDrag(offer);
        e.Handled = true;
    }

    private void OnDragLeave(object? sender, DragEventArgs e)
    {
        SetDrag(false);
        e.Handled = true;
    }

    private void OnDrop(object? sender, DragEventArgs e)
    {
        SetDrag(false);
        IEnumerable<string?> paths = e.DataTransfer?.TryGetFiles()
            ?.Select(static file => file.TryGetLocalPath())
            ?? [];
        string? iso = SourceStageViewModel.FirstExistingIsoPath(paths);
        if (iso is not null && DataContext is ISourceStageViewModel vm)
        {
            vm.SourceIsoPath = iso;
        }

        e.Handled = true;
    }

    private void SetDrag(bool on)
    {
        IsoPick.Classes.Set("drag", on);
        IsoStage.Classes.Set("drag", on);
    }
}
