using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

using WinMint.Orchestrator;

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
    AccountModeSelectionViewModel Mode { get; }
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

/// <summary>Portable OOBE vs bake-in AutoLogon (ADR-017). Customize defaults portable; curated emit forces bake-in.</summary>
public sealed partial class AccountModeSelectionViewModel : ObservableObject
{
    private readonly Action _changed;

    // ponytail: customize defaults portable; Use WinMint defaults / CuratedDefaults still force bake-in
    [ObservableProperty] private string _value = AccountProfile.OobeLocalMode;

    internal AccountModeSelectionViewModel(Action changed) => _changed = changed;

    public bool IsPortable =>
        string.Equals(Value, AccountProfile.OobeLocalMode, StringComparison.Ordinal);

    public bool IsBakeIn =>
        string.Equals(Value, AccountProfile.LocalAutoLogonMode, StringComparison.Ordinal);

    partial void OnValueChanged(string value)
    {
        OnPropertyChanged(nameof(IsPortable));
        OnPropertyChanged(nameof(IsBakeIn));
        _changed();
    }

    [RelayCommand]
    private void Select(string? mode)
    {
        if (string.Equals(mode, AccountProfile.OobeLocalMode, StringComparison.Ordinal)
            || string.Equals(mode, AccountProfile.LocalAutoLogonMode, StringComparison.Ordinal))
        {
            Value = mode!;
        }
    }

    internal void UseBakeIn() => Value = AccountProfile.LocalAutoLogonMode;
}

internal sealed partial class AccountStageViewModel : ObservableObject, IAccountStageViewModel
{
    private readonly Action _draftChanged;

    public AccountStageViewModel(Action draftChanged)
    {
        _draftChanged = draftChanged;
        Mode = new AccountModeSelectionViewModel(DraftChanged);
        ApplyBuildMachineDmaDefaults();
    }

    public AccountModeSelectionViewModel Mode { get; }

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
        Mode.IsPortable
        || (!string.IsNullOrWhiteSpace(Username) && !string.IsNullOrEmpty(Password));

    partial void OnUsernameChanged(string value) => DraftChanged();
    partial void OnPasswordChanged(string value) => DraftChanged();
    partial void OnRequireWifiChanged(bool value) => DraftChanged();
    partial void OnDmaEnabledChanged(bool value) => DraftChanged();
    partial void OnLocaleChanged(string value) => DraftChanged();
    partial void OnGeoIdChanged(string value) => DraftChanged();
    partial void OnTimeZoneChanged(string value) => DraftChanged();
    partial void OnLocationServicesChanged(bool value) => DraftChanged();

    [RelayCommand]
    private void UseBuildMachineDma() => ApplyBuildMachineDmaDefaults();

    private void DraftChanged() => _draftChanged();

    private void ApplyBuildMachineDmaDefaults()
    {
        HostDmaSettleSnapshot snapshot = HostDmaSettle.Capture();
        Locale = snapshot.Locale;
        GeoId = snapshot.GeoId.ToString(System.Globalization.CultureInfo.InvariantCulture);
        TimeZone = snapshot.TimeZoneId;
        LocationServices = snapshot.LocationServicesEnabled;
    }
}
