using System.Collections.ObjectModel;

using Avalonia.Platform.Storage;

using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

using WinMint.Orchestrator;

namespace WinMint.Wizard.ViewModels;

public interface ISourceStageViewModel
{
    string SourceIsoPath { get; set; }
    ObservableCollection<WimIndexInfo> WimIndexes { get; }
    WimIndexInfo? SelectedWimIndex { get; set; }
    bool IsWimPickerVisible { get; }
    bool IsWimProbeBusy { get; }
    IAsyncRelayCommand BrowseIsoCommand { get; }
    StageStatusViewModel Status { get; }
}

internal interface ISourceStageHost
{
    void SourceDraftChanged();
    Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> ListSourceIndexesAsync(CancellationToken cancellationToken);
    void ReportStageError(string code, string message);
    void ClearSourceProbeError();
}

internal sealed partial class SourceStageViewModel : ObservableObject, ISourceStageViewModel, IDisposable
{
    private readonly IStorageProvider? _storage;
    private readonly ISourceStageHost _host;
    private readonly int _buildMachineWimDefault = BuildMachineEdition.DefaultWimIndex();
    private CancellationTokenSource? _probeCts;
    private int _wimIndex;
    private bool _userChoseWimIndex;
    private bool _updatingWimPicker;

    public SourceStageViewModel(IStorageProvider? storage, ISourceStageHost host)
    {
        _storage = storage;
        _host = host;
        _wimIndex = _buildMachineWimDefault;
    }

    [ObservableProperty] private string _sourceIsoPath = "";
    [ObservableProperty] private WimIndexInfo? _selectedWimIndex;
    [ObservableProperty] private bool _isWimPickerVisible;
    [ObservableProperty] private bool _isWimProbeBusy;

    public ObservableCollection<WimIndexInfo> WimIndexes { get; } = [];
    public StageStatusViewModel Status { get; } = new();
    internal int WimIndex => _wimIndex;
    internal bool IsReady => !string.IsNullOrWhiteSpace(SourceIsoPath) && File.Exists(SourceIsoPath.Trim());

    partial void OnSourceIsoPathChanged(string value)
    {
        _userChoseWimIndex = false;
        _host.SourceDraftChanged();
        _ = ProbeSourceWimAsync();
    }

    partial void OnSelectedWimIndexChanged(WimIndexInfo? value)
    {
        if (value is null)
        {
            if (!_updatingWimPicker)
            {
                _host.SourceDraftChanged();
            }
            return;
        }

        if (value.Index != _wimIndex)
        {
            _userChoseWimIndex = true;
        }
        _wimIndex = value.Index;
        _host.SourceDraftChanged();
    }

    [RelayCommand]
    private async Task BrowseIsoAsync()
    {
        if (_storage is null)
        {
            return;
        }

        IReadOnlyList<IStorageFile> files = await _storage.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Choose Source ISO",
            AllowMultiple = false,
            FileTypeFilter = [new FilePickerFileType("ISO") { Patterns = ["*.iso"] }],
        }).ConfigureAwait(true);
        string? path = files.Count == 0 ? null : files[0].TryGetLocalPath();
        if (!string.IsNullOrEmpty(path))
        {
            SourceIsoPath = path;
        }
    }

    private async Task ProbeSourceWimAsync()
    {
        _probeCts?.Cancel();
        CancellationTokenSource operation = new();
        _probeCts = operation;
        CancellationToken cancellationToken = operation.Token;

        WimIndexes.Clear();
        _updatingWimPicker = true;
        SelectedWimIndex = null;
        _updatingWimPicker = false;
        IsWimPickerVisible = false;
        if (!IsReady)
        {
            IsWimProbeBusy = false;
            if (ReferenceEquals(_probeCts, operation))
            {
                _probeCts = null;
            }
            operation.Dispose();
            return;
        }

        IsWimProbeBusy = true;
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                Result<IReadOnlyList<WimIndexInfo>, Failure> result =
                    await _host.ListSourceIndexesAsync(cancellationToken).ConfigureAwait(true);
                if (cancellationToken.IsCancellationRequested)
                {
                    return;
                }
                if (!result.IsOk && result.Error.Code == "wizardSession.probe.stale")
                {
                    // The session revision changed for another stage; settle the current source identity.
                    continue;
                }
                if (!result.IsOk)
                {
                    _userChoseWimIndex = false;
                    _wimIndex = _buildMachineWimDefault;
                    _host.ReportStageError(result.Error.Code, result.Error.Message);
                    return;
                }

                foreach (WimIndexInfo row in result.Value)
                {
                    WimIndexes.Add(row);
                }

                int selected = WimIndexInfo.ResolveSelection(
                    result.Value,
                    _wimIndex,
                    _userChoseWimIndex,
                    _buildMachineWimDefault);
                _wimIndex = selected;
                _updatingWimPicker = true;
                SelectedWimIndex = WimIndexes.FirstOrDefault(row => row.Index == selected);
                _updatingWimPicker = false;
                IsWimPickerVisible = true;
                if (!result.Value.Any(row => row.Index == selected))
                {
                    _host.ReportStageError(
                        "wim.probe.indexMissing",
                        $"Source ISO does not contain WIM index {selected}. Select an available edition.");
                }
                else
                {
                    _host.ClearSourceProbeError();
                }
                return;
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        finally
        {
            if (ReferenceEquals(_probeCts, operation))
            {
                _probeCts = null;
                IsWimProbeBusy = false;
            }
            operation.Dispose();
        }
    }

    internal static string? FirstExistingIsoPath(IEnumerable<string?> candidates)
    {
        foreach (string? candidate in candidates)
        {
            if (string.IsNullOrWhiteSpace(candidate))
            {
                continue;
            }

            string path = candidate.Trim();
            if (path.EndsWith(".iso", StringComparison.OrdinalIgnoreCase) && File.Exists(path))
            {
                return path;
            }
        }

        return null;
    }

    public void Dispose()
    {
        _probeCts?.Cancel();
        _probeCts?.Dispose();
        _probeCts = null;
    }
}
