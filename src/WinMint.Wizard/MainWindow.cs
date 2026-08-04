using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using WinMint.Orchestrator;

namespace WinMint.Wizard;

public sealed class MainWindow : Window
{
    private readonly TextBox _username = Field("winmint");
    private readonly TextBox _password = PasswordField("winmint");
    private readonly CheckBox _requireWifi = new() { Content = "Require Wi‑Fi during OOBE", IsChecked = false };
    private readonly CheckBox _dmaEnabled = new() { Content = "DMA enabled", IsChecked = true };
    private readonly TextBox _locale = Field("en-GB");
    private readonly TextBox _geoId = Field("242");
    private readonly TextBox _timeZone = Field("GMT Standard Time");
    private readonly CheckBox _location = new() { Content = "Location services", IsChecked = true };
    private readonly ComboBox _preset;
    private readonly TextBox _winget = IdListBox();
    private readonly TextBox _wingetNeedsReboot = IdListBox();
    private readonly TextBox _scoop = IdListBox();
    private readonly TextBox _scoopNeedsReboot = IdListBox();
    private readonly TextBox _wsl = IdListBox();
    private readonly TextBox _wslNeedsReboot = IdListBox();
    private readonly TextBox _removeCapabilities = IdListBox();
    private readonly TextBox _disableOptionalFeatures = IdListBox();
    private readonly TextBlock _status = new()
    {
        TextWrapping = TextWrapping.Wrap,
        Margin = new Avalonia.Thickness(0, 12, 0, 0),
    };
    private readonly TextBox _preview = new()
    {
        IsReadOnly = true,
        AcceptsReturn = true,
        TextWrapping = TextWrapping.NoWrap,
        FontFamily = new FontFamily("Consolas"),
        MinHeight = 160,
        PlaceholderText = "Profile JSON preview after Validate",
    };

    private byte[]? _lastProfileUtf8;

    public MainWindow()
    {
        Title = "WinMint Wizard";
        Width = 640;
        Height = 960;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        _preset = new ComboBox
        {
            ItemsSource = new[] { KeepFlagPresets.Empty, KeepFlagPresets.Acceptance },
            SelectedIndex = 1,
            MinWidth = 180,
        };

        Button validate = new() { Content = "Validate / Plan" };
        validate.Click += (_, _) => OnValidate();

        Button save = new() { Content = "Save Profile JSON…" };
        save.Click += async (_, _) => await OnSaveAsync();

        Button israelDma = new() { Content = "Fill Israel DMA" };
        israelDma.Click += (_, _) =>
        {
            _locale.Text = "en-US";
            _geoId.Text = "117";
            _timeZone.Text = "Israel Standard Time";
            _location.IsChecked = true;
            _dmaEnabled.IsChecked = true;
        };

        Content = new ScrollViewer
        {
            Content = new StackPanel
            {
                Margin = new Avalonia.Thickness(16),
                Spacing = 8,
                Children =
                {
                    Heading("Account"),
                    Labeled("Username", _username),
                    Labeled("Password", _password),
                    _requireWifi,
                    Heading("DMA settle"),
                    _dmaEnabled,
                    Labeled("Locale", _locale),
                    Labeled("GeoId", _geoId),
                    Labeled("Time zone", _timeZone),
                    _location,
                    israelDma,
                    Heading("Keep-flag preset (host expands → remove-lists)"),
                    Labeled("Preset", _preset),
                    Heading("Capabilities / features (newline ids; empty = preset pins)"),
                    Labeled("removeCapabilities", _removeCapabilities),
                    Labeled("disableOptionalFeatures", _disableOptionalFeatures),
                    Heading("Packages (newline-separated ids; empty = stubs only)"),
                    Labeled("winget", _winget),
                    Labeled("wingetNeedsReboot (subset of winget)", _wingetNeedsReboot),
                    Labeled("scoop", _scoop),
                    Labeled("scoopNeedsReboot (subset of scoop)", _scoopNeedsReboot),
                    Labeled("wsl (distro names)", _wsl),
                    Labeled("wslNeedsReboot (subset of wsl)", _wslNeedsReboot),
                    new StackPanel
                    {
                        Orientation = Orientation.Horizontal,
                        Spacing = 8,
                        Children = { validate, save },
                    },
                    _status,
                    Heading("Composed Profile"),
                    _preview,
                },
            },
        };
    }

    private void OnValidate()
    {
        WizardSessionResult result = RunSession();
        _status.Text = result.Message;
        _status.Foreground = result.Succeeded ? Brushes.DarkGreen : Brushes.DarkRed;
        if (result.Succeeded)
        {
            _lastProfileUtf8 = result.ProfileUtf8;
            _preview.Text = result.ProfileJson;
        }
        else
        {
            _lastProfileUtf8 = null;
        }
    }

    private async System.Threading.Tasks.Task OnSaveAsync()
    {
        WizardSessionResult result = RunSession();
        _status.Text = result.Message;
        _status.Foreground = result.Succeeded ? Brushes.DarkGreen : Brushes.DarkRed;
        if (!result.Succeeded || result.ProfileUtf8 is null || result.ProfileJson is null)
        {
            _lastProfileUtf8 = null;
            return;
        }

        _lastProfileUtf8 = result.ProfileUtf8;
        _preview.Text = result.ProfileJson;

        IStorageProvider? storage = StorageProvider;
        if (storage is null)
        {
            _status.Text = "Save failed: no storage provider.";
            _status.Foreground = Brushes.DarkRed;
            return;
        }

        IStorageFile? file = await storage.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Save WinMint Profile",
            SuggestedFileName = "winmint.profile.json",
            FileTypeChoices =
            [
                new FilePickerFileType("Profile JSON") { Patterns = ["*.json"] },
            ],
        });

        if (file is null)
        {
            return;
        }

        string? path = file.TryGetLocalPath();
        if (string.IsNullOrEmpty(path))
        {
            _status.Text = "Save failed: could not resolve local path.";
            _status.Foreground = Brushes.DarkRed;
            return;
        }

        await File.WriteAllBytesAsync(path, _lastProfileUtf8);
        _status.Text = $"Saved {_lastProfileUtf8.Length} bytes → {path}\n{result.Message}";
        _status.Foreground = Brushes.DarkGreen;
    }

    private WizardSessionResult RunSession()
    {
        string preset = (_preset.SelectedItem as string) ?? "";
        return WizardSession.ComposeAndPlan(
            preset,
            _username.Text ?? "",
            _password.Text ?? "",
            _requireWifi.IsChecked == true,
            _dmaEnabled.IsChecked == true,
            _locale.Text ?? "",
            _geoId.Text ?? "",
            _timeZone.Text ?? "",
            _location.IsChecked == true,
            _winget.Text ?? "",
            _wingetNeedsReboot.Text ?? "",
            _scoop.Text ?? "",
            _scoopNeedsReboot.Text ?? "",
            _wsl.Text ?? "",
            _wslNeedsReboot.Text ?? "",
            _removeCapabilities.Text ?? "",
            _disableOptionalFeatures.Text ?? "");
    }

    private static TextBlock Heading(string text) => new()
    {
        Text = text,
        FontWeight = FontWeight.SemiBold,
        Margin = new Avalonia.Thickness(0, 12, 0, 0),
    };

    private static StackPanel Labeled(string label, Control control) => new()
    {
        Spacing = 4,
        Children =
        {
            new TextBlock { Text = label },
            control,
        },
    };

    private static TextBox Field(string text) => new() { Text = text };

    private static TextBox PasswordField(string text) => new() { Text = text, PasswordChar = '•' };

    private static TextBox IdListBox() => new()
    {
        AcceptsReturn = true,
        TextWrapping = TextWrapping.NoWrap,
        MinHeight = 56,
        FontFamily = new FontFamily("Consolas"),
        PlaceholderText = "one id per line",
    };
}
