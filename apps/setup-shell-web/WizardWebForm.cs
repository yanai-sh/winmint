using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace WinMintSetupShell;

internal sealed class WizardWebForm : Form
{
    private const string VirtualHost = "winmint.setup";

    private readonly AppOptions _options;
    private readonly ShellLogger _logger;
    private readonly string _repoRoot;
    private readonly WebView2 _webView;

    public WizardWebForm(AppOptions options, ShellLogger logger, string repoRoot)
    {
        _options = options;
        _logger = logger;
        _repoRoot = repoRoot;

        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.CenterScreen;
        var work = Screen.FromPoint(Cursor.Position).WorkingArea;
        ClientSize = new Size(
            Math.Clamp((int)(work.Width * 0.92), 1280, 1680),
            Math.Clamp((int)(work.Height * 0.9), 800, 1050));
        MinimumSize = new Size(1100, 720);
        ShowInTaskbar = true;
        Text = "WinMint";
        BackColor = Color.FromArgb(0x11, 0x16, 0x1d);
        KeyPreview = true;

        _webView = new WebView2
        {
            Dock = DockStyle.Fill,
            DefaultBackgroundColor = Color.FromArgb(0x11, 0x16, 0x1d)
        };
        Controls.Add(_webView);

        Resize += (_, _) => PostWindowState();
        Shown += (_, _) => BeginInitializeWebView();
    }

    private void BeginInitializeWebView()
    {
        _ = InitializeWebViewSafeAsync();
    }

    protected override bool ProcessDialogKey(Keys keyData)
    {
        if (_options.Preview && keyData == Keys.Escape)
        {
            Close();
            return true;
        }

        return base.ProcessDialogKey(keyData);
    }

    private async Task InitializeWebViewSafeAsync()
    {
        try
        {
            await InitializeWebViewAsync();
        }
        catch (Exception ex)
        {
            _logger.Info($"presenter=webview2 wizard init-failed: {ex.Message}");
            Environment.Exit(1);
        }
    }

    private async Task InitializeWebViewAsync()
    {
        var wizardPath = Path.Combine(_options.ShellRoot, "wizard.html");
        if (!File.Exists(wizardPath))
        {
            throw new FileNotFoundException($"Build wizard UI is missing: {wizardPath}");
        }

        await _webView.EnsureCoreWebView2Async();
        var core = _webView.CoreWebView2;
        core.Settings.AreDefaultContextMenusEnabled = false;
        core.Settings.AreDevToolsEnabled = _options.Preview;
        core.Settings.IsStatusBarEnabled = false;
        core.Settings.IsZoomControlEnabled = false;

        core.SetVirtualHostNameToFolderMapping(
            VirtualHost,
            _options.ShellRoot,
            CoreWebView2HostResourceAccessKind.Allow);

        core.WebMessageReceived += (_, e) => HandleWebMessage(e.TryGetWebMessageAsString());
        core.NavigationCompleted += async (_, e) =>
        {
            if (e.IsSuccess)
            {
                _logger.Info("presenter=webview2 wizard navigation-complete");
                await core.ExecuteScriptAsync(
                    """
                    (() => {
                      const style = document.createElement('style');
                      style.textContent = `
                        .wizard-titlebar { -webkit-app-region: drag; }
                        .titlebar-controls, .win-btn, button, input, select, textarea, a, label, .chip, .toggle { -webkit-app-region: no-drag; }
                      `;
                      document.head.appendChild(style);
                    })();
                    """);
                PostWindowState();
            }
        };

        if (_options.Preview)
        {
            await core.AddScriptToExecuteOnDocumentCreatedAsync(
                """
                window.addEventListener('keydown', (e) => {
                    if (e.key === 'Escape' && window.chrome && window.chrome.webview) {
                        window.chrome.webview.postMessage(JSON.stringify({ type: 'previewClose' }));
                    }
                });
                """);
        }

        core.Navigate($"https://{VirtualHost}/wizard.html");
        _logger.Info($"presenter=webview2 wizard repoRoot={_repoRoot}");
    }

    private void HandleWebMessage(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return;
        }

        void Dispatch()
        {
            JsonObject? message;
            try
            {
                message = JsonNode.Parse(raw) as JsonObject;
            }
            catch (JsonException ex)
            {
                _logger.Info($"wizard message parse warning: {ex.Message}");
                return;
            }

            if (message is null)
            {
                return;
            }

            var type = message["type"]?.GetValue<string>() ?? "";
            if (string.Equals(type, "previewClose", StringComparison.Ordinal))
            {
                Close();
                return;
            }

            if (string.Equals(type, "windowControl", StringComparison.Ordinal))
            {
                HandleWindowControl(message["action"]?.GetValue<string>() ?? "");
                return;
            }

            var id = message["id"]?.GetValue<string>() ?? "";
            if (string.Equals(type, "pickIso", StringComparison.Ordinal))
            {
                try
                {
                    _logger.Info("wizard pickIso requested");
                    var response = PickIsoOnUiThread();
                    PostReply(id, true, "pickIso", response, "");
                }
                catch (Exception ex)
                {
                    _logger.Info($"wizard pickIso failed: {ex.Message}");
                    PostReply(id, false, "pickIso", new JsonObject(), ex.Message);
                }

                return;
            }

            _ = Task.Run(() => DispatchMessageAsync(id, type, message));
        }

        if (InvokeRequired)
        {
            BeginInvoke(Dispatch);
            return;
        }

        Dispatch();
    }

    private void HandleWindowControl(string action)
    {
        switch (action)
        {
            case "minimize":
                WindowState = FormWindowState.Minimized;
                break;
            case "maximize":
                WindowState = WindowState == FormWindowState.Maximized
                    ? FormWindowState.Normal
                    : FormWindowState.Maximized;
                break;
            case "close":
                Close();
                break;
        }

        PostWindowState();
    }

    private void PostWindowState()
    {
        if (IsDisposed || _webView.CoreWebView2 is null)
        {
            return;
        }

        var state = WindowState == FormWindowState.Maximized ? "maximized" : "normal";
        var payload = new JsonObject
        {
            ["type"] = "windowState",
            ["state"] = state
        };
        PostHostMessage(payload);
    }

    private async Task DispatchMessageAsync(string id, string type, JsonObject message)
    {
        JsonObject response;
        try
        {
            response = type switch
            {
                "probeIso" => ProbeIso(message),
                "saveWizardSettings" => SaveWizardSettings(message),
                "saveIntent" => SaveWizardSettings(message),
                "generateProfile" => GenerateProfile(),
                "startDryRun" => StartDryRun(),
                "readBuildDelta" => ReadBuildDelta(message),
                "getRepoRoot" => new JsonObject { ["repoRoot"] = _repoRoot },
                _ => throw new InvalidOperationException($"Unknown wizard message type: {type}")
            };
            PostReply(id, true, type, response, "");
        }
        catch (Exception ex)
        {
            PostReply(id, false, type, new JsonObject(), ex.Message);
        }
    }

    private JsonObject PickIsoOnUiThread()
    {
        Activate();
        TopMost = true;
        TopMost = false;
        using var dialog = new OpenFileDialog
        {
            Title = "Select Windows ISO",
            Filter = "ISO images (*.iso)|*.iso|All files (*.*)|*.*",
            CheckFileExists = true
        };

        var owner = new Win32Window(Handle);
        if (dialog.ShowDialog(owner) != DialogResult.OK)
        {
            return new JsonObject { ["cancelled"] = true };
        }

        return new JsonObject
        {
            ["cancelled"] = false,
            ["path"] = dialog.FileName
        };
    }

    private static JsonObject ToReplyObject(JsonNode node) =>
        node is JsonObject obj ? obj : JsonNode.Parse(node.ToJsonString())!.AsObject();

    private JsonObject ProbeIso(JsonObject message)
    {
        var path = message["path"]?.GetValue<string>() ?? "";
        var result = WizardBridge.RunBridgeScript(_repoRoot, "Get-UiIsoMetadata.ps1", new[]
        {
            "-Path", path
        }, includeRepositoryRoot: false);
        return ToReplyObject(result);
    }

    private JsonObject SaveWizardSettings(JsonObject message)
    {
        var settings = message["settings"] ?? message["intent"];
        if (settings is null)
        {
            throw new InvalidOperationException("saveWizardSettings requires a settings object.");
        }

        WizardBridge.SaveWizardSettings(_repoRoot, settings);
        return new JsonObject { ["path"] = WizardBridge.WizardSettingsPath(_repoRoot) };
    }

    private JsonObject GenerateProfile()
    {
        var outputPath = WizardBridge.ProfilePath(_repoRoot);
        WizardBridge.RunBridgeScript(_repoRoot, "New-UiBuildProfile.ps1", new[]
        {
            "-SettingsPath", WizardBridge.IntentPath(_repoRoot),
            "-OutputPath", outputPath
        });
        return new JsonObject { ["profilePath"] = outputPath };
    }

    private JsonObject StartDryRun()
    {
        var profilePath = WizardBridge.ProfilePath(_repoRoot);
        var result = WizardBridge.RunBridgeScript(_repoRoot, "Start-UiBuildFromProfile.ps1", new[]
        {
            "-ProfilePath", profilePath,
            "-DryRun"
        });
        return ToReplyObject(result);
    }

    private JsonObject ReadBuildDelta(JsonObject message)
    {
        var path = message["path"]?.GetValue<string>() ?? "";
        if (string.IsNullOrWhiteSpace(path))
        {
            path = Path.Combine(_repoRoot, "output", "WinMint-BuildDelta.json");
        }

        var summary = WizardBridge.SummarizeBuildDelta(path);
        return ToReplyObject(summary);
    }

    private void PostReply(string id, bool ok, string type, JsonObject body, string error)
    {
        var payload = new JsonObject
        {
            ["id"] = id,
            ["ok"] = ok,
            ["type"] = $"{type}Result",
            ["error"] = error,
            ["body"] = body
        };

        if (IsDisposed)
        {
            return;
        }

        void Send()
        {
            if (_webView.CoreWebView2 is null)
            {
                return;
            }

            PostHostMessage(payload);
        }

        if (InvokeRequired)
        {
            BeginInvoke(Send);
            return;
        }

        Send();
    }

    private void PostHostMessage(JsonObject payload)
    {
        if (_webView.CoreWebView2 is null)
        {
            return;
        }

        _webView.CoreWebView2.PostWebMessageAsString(payload.ToJsonString());
    }

    private sealed class Win32Window : IWin32Window
    {
        public Win32Window(nint handle) => Handle = handle;
        public nint Handle { get; }
    }
}
