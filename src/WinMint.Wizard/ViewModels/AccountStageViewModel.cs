using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace WinMint.Wizard.ViewModels;

public sealed partial class StageStatusViewModel : ObservableObject
{
    [ObservableProperty] private string _message = "";
    [ObservableProperty] private bool _isError;

    internal void Set(string message, bool isError)
    {
        Message = message;
        IsError = isError;
    }

    internal void Clear() => Set("", false);
}

public interface IAccountStageViewModel
{
    string Username { get; set; }
    string Password { get; set; }
    bool RequireWifi { get; set; }
    string Locale { get; set; }
    string GeoId { get; set; }
    string TimeZone { get; set; }
    bool LocationServices { get; set; }
    IRelayCommand UseBuildMachineDmaCommand { get; }
    StageStatusViewModel Status { get; }
}

internal sealed partial class AccountStageViewModel : ObservableObject, IAccountStageViewModel
{
    private readonly Action _draftChanged;

    public AccountStageViewModel(Action draftChanged)
    {
        _draftChanged = draftChanged;
        ApplyBuildMachineDmaDefaults();
    }

    [ObservableProperty] private string _username = "winmint";
    [ObservableProperty] private string _password = "";
    [ObservableProperty] private bool _requireWifi;
    [ObservableProperty] private bool _dmaEnabled = true;
    [ObservableProperty] private string _locale = "en-GB";
    [ObservableProperty] private string _geoId = "242";
    [ObservableProperty] private string _timeZone = "GMT Standard Time";
    [ObservableProperty] private bool _locationServices = true;

    public StageStatusViewModel Status { get; } = new();
    internal bool IdentityReady =>
        !string.IsNullOrWhiteSpace(Username) && !string.IsNullOrEmpty(Password);

    partial void OnUsernameChanged(string value) => _draftChanged();
    partial void OnPasswordChanged(string value) => _draftChanged();
    partial void OnRequireWifiChanged(bool value) => _draftChanged();
    partial void OnDmaEnabledChanged(bool value) => _draftChanged();
    partial void OnLocaleChanged(string value) => _draftChanged();
    partial void OnGeoIdChanged(string value) => _draftChanged();
    partial void OnTimeZoneChanged(string value) => _draftChanged();
    partial void OnLocationServicesChanged(bool value) => _draftChanged();

    [RelayCommand]
    private void UseBuildMachineDma() => ApplyBuildMachineDmaDefaults();

    private void ApplyBuildMachineDmaDefaults()
    {
        BuildMachineDmaSnapshot snapshot = BuildMachineDma.Capture();
        Locale = snapshot.Locale;
        GeoId = snapshot.GeoId.ToString(System.Globalization.CultureInfo.InvariantCulture);
        TimeZone = snapshot.TimeZoneId;
        LocationServices = snapshot.LocationServicesEnabled;
    }
}
