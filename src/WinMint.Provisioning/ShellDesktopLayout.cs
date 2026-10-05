using System.Globalization;
using System.Runtime.Versioning;
using System.Text.Json;

using Windows.Win32;
using Windows.Win32.UI.WindowsAndMessaging;

namespace WinMint.Provisioning;

internal static class ShellDesktopLayout
{
    public const string GuestDesktopRoot = @"C:\Windows\WinMint\desktop";
    public const string YasbWingetId = "AmN.yasb";
    public const string KomorebiWingetId = "LGUG2Z.komorebi";

    public static string DefaultThideInstallDir =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "WinMint",
            "thide");

    public static string DefaultYasbConfigDir =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".config",
            "yasb");

    public static string DefaultKomorebiConfigDir =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".config",
            "komorebi");

    public static string DefaultWhkdrcPath =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".config",
            "whkdrc");

    public static string SelectYasbVariant(bool komorebi) => komorebi ? "komorebi" : "native";

    public static string BuildKomorebiMonitorsJson(int monitorCount)
    {
        if (monitorCount < 1)
        {
            monitorCount = 1;
        }

        List<string> monitors = [];
        for (int m = 1; m <= monitorCount; m++)
        {
            List<string> workspaces = [];
            for (int w = 1; w <= 4; w++)
            {
                workspaces.Add($$"""{"name":"winmint-{{m}}-{{w}}","layout":"BSP"}""");
            }

            monitors.Add($$"""{"workspaces":[{{string.Join(",", workspaces)}}]}""");
        }

        return $"[{string.Join(",", monitors)}]";
    }

    public static string BuildDisplayIndexPreferencesJson(IReadOnlyList<string?> serials)
    {
        ArgumentNullException.ThrowIfNull(serials);
        List<string> pairs = [];
        for (int i = 0; i < serials.Count; i++)
        {
            string? serial = serials[i];
            if (!string.IsNullOrWhiteSpace(serial))
            {
                pairs.Add(
                    $"{JsonString(i.ToString(CultureInfo.InvariantCulture))}:{JsonString(serial)}");
            }
        }

        return pairs.Count == 0 ? "{}" : "{" + string.Join(",", pairs) + "}";
    }

    public static string RenderKomorebiConfig(
        string template,
        string monitorsJson,
        string displayPrefsJson)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(template);
        return template
            .Replace("{{WINMINT_MONITORS_JSON}}", monitorsJson, StringComparison.Ordinal)
            .Replace("{{WINMINT_DISPLAY_INDEX_PREFERENCES_JSON}}", displayPrefsJson, StringComparison.Ordinal);
    }

    public static List<string?> ParseMonitorInfoSerials(string json)
    {
        List<string?> serials = [];
        if (string.IsNullOrWhiteSpace(json))
        {
            return serials;
        }

        try
        {
            using JsonDocument doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind is not JsonValueKind.Array)
            {
                return serials;
            }

            foreach (JsonElement monitor in doc.RootElement.EnumerateArray())
            {
                string? serial = TryReadSerial(monitor);
                serials.Add(serial);
            }
        }
        catch (JsonException)
        {
            // ponytail: best-effort parse only
        }

        return serials;
    }

    [SupportedOSPlatform("windows10.0.19041.0")]
    public static int TryGetConnectedMonitorCount()
    {
        if (!OperatingSystem.IsWindows())
        {
            return 1;
        }

        int count = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CMONITORS);
        return count > 0 ? count : 1;
    }

    private static string JsonString(string value) =>
        $"\"{value.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal)}\"";

    private static string? TryReadSerial(JsonElement monitor)
    {
        if (monitor.TryGetProperty("serial_number_id", out JsonElement direct))
        {
            return direct.GetString();
        }

        foreach (string name in new[] { "id", "serial", "serial_number" })
        {
            if (monitor.TryGetProperty(name, out JsonElement nested))
            {
                return nested.GetString();
            }
        }

        return null;
    }
}
