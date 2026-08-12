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
    SourceLaneViewModel Lane { get; }
    IAsyncRelayCommand BrowseIsoCommand { get; }
    IRelayCommand<string?> SelectLaneCommand { get; }
    StageStatusViewModel Status { get; }
}

internal interface ISourceStageHost
{
    void SourceDraftChanged();
    Task<Result<SourceMediaReview, Failure>> SettleSourceProbeAsync(CancellationToken cancellationToken);
    void ReportStageError(string code, string message);
    void ClearSourceProbeError();
}

public sealed partial class SourceLaneViewModel : ObservableObject
{
    private readonly Func<ImageQualityLane> _current;
    internal SourceLaneViewModel(Func<ImageQualityLane> current) => _current = current;
    public bool IsTest => _current() == ImageQualityLane.Test;
    public bool IsRelease => _current() == ImageQualityLane.Release;
    internal void Refresh()
    {
        OnPropertyChanged(nameof(IsTest));
        OnPropertyChanged(nameof(IsRelease));
    }
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
        Lane = new SourceLaneViewModel(() => ImageQuality);
    }

    [ObservableProperty] private string _sourceIsoPath = "";
    [ObservableProperty] private ImageQualityLane _imageQuality = ImageQualityLane.Test;
    [ObservableProperty] private WimIndexInfo? _selectedWimIndex;
    [ObservableProperty] private bool _isWimPickerVisible;
    [ObservableProperty] private bool _isWimProbeBusy;

    public ObservableCollection<WimIndexInfo> WimIndexes { get; } = [];
    public StageStatusViewModel Status { get; } = new();
    public SourceLaneViewModel Lane { get; }
    internal int WimIndex => _wimIndex;
    internal bool IsReady => !string.IsNullOrWhiteSpace(SourceIsoPath) && File.Exists(SourceIsoPath.Trim());

    partial void OnSourceIsoPathChanged(string value)
    {
        _userChoseWimIndex = false;
        _host.SourceDraftChanged();
        _ = ProbeSourceWimAsync();
    }

    partial void OnImageQualityChanged(ImageQualityLane value)
    {
        Lane.Refresh();
        _host.SourceDraftChanged();
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
    private void SelectLane(string? lane)
    {
        if (Enum.TryParse(lane, ignoreCase: true, out ImageQualityLane parsed))
        {
            ImageQuality = parsed;
        }
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
                Result<SourceMediaReview, Failure> result =
                    await _host.SettleSourceProbeAsync(cancellationToken).ConfigureAwait(true);
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

                foreach (WimIndexInfo row in result.Value.Indexes)
                {
                    WimIndexes.Add(row);
                }

                int selected = SourceWimProbe.ResolveSelection(
                    result.Value.Indexes,
                    _wimIndex,
                    _userChoseWimIndex,
                    _buildMachineWimDefault);
                _wimIndex = selected;
                _updatingWimPicker = true;
                SelectedWimIndex = WimIndexes.FirstOrDefault(row => row.Index == selected);
                _updatingWimPicker = false;
                IsWimPickerVisible = true;
                if (result.Value.SelectionMismatch is { } mismatch)
                {
                    _host.ReportStageError(mismatch.Code, mismatch.Message + " Select an available edition.");
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

    public void Dispose()
    {
        _probeCts?.Cancel();
        _probeCts?.Dispose();
        _probeCts = null;
    }
}
