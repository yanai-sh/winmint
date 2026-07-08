using System.Diagnostics;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace WinMintSetupShell;

internal sealed class SetupShellWebForm : Form
{
    private const string VirtualHost = "winmint.setup";

    private readonly AppOptions _options;
    private readonly ShellLogger _logger;
    private readonly WebView2 _webView;
    private readonly System.Windows.Forms.Timer _pollTimer;
    private readonly System.Windows.Forms.Timer _guardTimer;

    private SetupShellControl _control = new();
    private DateTimeOffset? _firstPaintAt;
    private DateTimeOffset? _terminalPhaseAt;
    private bool _navigationLogged;

    public SetupShellWebForm(AppOptions options, ShellLogger logger)
    {
        _options = options;
        _logger = logger;

        var bounds = MonitorUtil.GetPrimaryMonitorBounds();
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Bounds = new Rectangle(bounds.Left, bounds.Top, bounds.Width, bounds.Height);
        TopMost = !_options.Preview;
        ShowInTaskbar = _options.Preview;
        BackColor = Color.FromArgb(0x11, 0x16, 0x1d);
        KeyPreview = true;

        _webView = new WebView2
        {
            Dock = DockStyle.Fill,
            DefaultBackgroundColor = Color.FromArgb(0x11, 0x16, 0x1d)
        };
        Controls.Add(_webView);

        _pollTimer = new System.Windows.Forms.Timer { Interval = Math.Max(500, _options.PollMs) };
        _pollTimer.Tick += (_, _) => OnPollTick();

        _guardTimer = new System.Windows.Forms.Timer { Interval = 250 };
        _guardTimer.Tick += (_, _) => DesktopGuard.Tick(Handle, _options.Preview);

        Shown += (_, _) => BeginInitializeWebView();
    }

    private void BeginInitializeWebView()
    {
        _ = InitializeWebViewSafeAsync();
    }

    private async Task InitializeWebViewSafeAsync()
    {
        try
        {
            await InitializeWebViewAsync();
        }
        catch (Exception ex)
        {
            _logger.Info($"presenter=webview2 init-failed: {ex.Message}");
            Environment.Exit(1);
        }
    }

    protected override bool ProcessDialogKey(Keys keyData)
    {
        if (_options.Preview && keyData == Keys.Escape)
        {
            _logger.Info("preview close escape");
            Close();
            return true;
        }

        return base.ProcessDialogKey(keyData);
    }

    private async Task InitializeWebViewAsync()
    {
        var indexPath = Path.Combine(_options.ShellRoot, "index.html");
        if (!File.Exists(indexPath))
        {
            throw new FileNotFoundException($"Setup shell UI is missing: {indexPath}");
        }

        try
        {
            await _webView.EnsureCoreWebView2Async();
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException($"WebView2 runtime is not available: {ex.Message}", ex);
        }

        var core = _webView.CoreWebView2;
        core.Settings.AreDefaultContextMenusEnabled = false;
        core.Settings.AreDevToolsEnabled = _options.Preview;
        core.Settings.IsStatusBarEnabled = false;
        core.Settings.IsZoomControlEnabled = false;

        core.SetVirtualHostNameToFolderMapping(
            VirtualHost,
            _options.ShellRoot,
            CoreWebView2HostResourceAccessKind.Allow);

        core.NavigationCompleted += (_, e) =>
        {
            if (!e.IsSuccess)
            {
                _logger.Info($"presenter=webview2 navigation-failed={e.WebErrorStatus}");
                return;
            }

            if (!_navigationLogged)
            {
                _navigationLogged = true;
                _firstPaintAt = DateTimeOffset.Now;
                _logger.Info("presenter=webview2 navigation-complete");
            }
        };

        core.WebMessageReceived += (_, e) =>
        {
            var message = e.TryGetWebMessageAsString();
            if (_options.Preview && string.Equals(message, "previewClose", StringComparison.Ordinal))
            {
                _logger.Info("preview close escape");
                BeginInvoke(Close);
                return;
            }

            if (string.Equals(message, "openLogs", StringComparison.Ordinal))
            {
                OpenLogsFolder();
            }
        };

        if (_options.Preview)
        {
            await core.AddScriptToExecuteOnDocumentCreatedAsync(
                """
                window.addEventListener('keydown', (e) => {
                    if (e.key === 'Escape' && window.chrome && window.chrome.webview) {
                        window.chrome.webview.postMessage('previewClose');
                    }
                });
                """);
        }

        PollControl(forceLog: true);
        core.Navigate($"https://{VirtualHost}/index.html");
        _pollTimer.Start();
        _guardTimer.Start();
        _logger.Info($"presenter=webview2 shellRoot={_options.ShellRoot}");
    }

    private void OnPollTick()
    {
        PollControl(forceLog: false);
        if (ShouldClose())
        {
            Close();
        }
    }

    private void PollControl(bool forceLog)
    {
        try
        {
            if (!File.Exists(_options.ControlPath))
            {
                return;
            }

            var json = File.ReadAllText(_options.ControlPath);
            var control = JsonSerializer.Deserialize(json, SetupShellJsonContext.Default.SetupShellControl);
            if (control is null)
            {
                return;
            }

            if (forceLog)
            {
                _logger.Info($"control phase={control.Phase}");
            }

            if (IsTerminalPhase(control.Phase) && !IsTerminalPhase(_control.Phase))
            {
                _terminalPhaseAt = DateTimeOffset.Now;
                _logger.Info($"control terminal phase={control.Phase}");
            }

            _control = control;
        }
        catch (Exception ex)
        {
            _logger.Info($"control poll warning: {ex.Message}");
        }
    }

    private bool ShouldClose()
    {
        if (!IsTerminalPhase(_control.Phase))
        {
            return false;
        }

        if (_firstPaintAt is null)
        {
            return false;
        }

        _terminalPhaseAt ??= DateTimeOffset.Now;
        var dwellMs = string.Equals(_control.Phase, "complete", StringComparison.OrdinalIgnoreCase)
            ? _options.MinCompleteDwellMs
            : _options.MinStartDwellMs;
        return (DateTimeOffset.Now - _terminalPhaseAt.Value).TotalMilliseconds >= dwellMs;
    }

    private static bool IsTerminalPhase(string phase) =>
        phase is "complete" or "failed" or "reboot";

    private void OpenLogsFolder()
    {
        try
        {
            if (!File.Exists(_options.StatusPath))
            {
                return;
            }

            var json = File.ReadAllText(_options.StatusPath);
            var status = JsonSerializer.Deserialize(json, SetupShellJsonContext.Default.SetupShellStatus);
            if (status is null || string.IsNullOrWhiteSpace(status.LogDir))
            {
                return;
            }

            if (Directory.Exists(status.LogDir))
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = status.LogDir,
                    UseShellExecute = true
                });
            }
        }
        catch (Exception ex)
        {
            _logger.Info($"openLogs warning: {ex.Message}");
        }
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        _pollTimer.Stop();
        _guardTimer.Stop();
        _webView.Dispose();
        base.OnFormClosed(e);
    }
}
