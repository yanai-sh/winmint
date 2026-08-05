using System.Text;
using System.Text.Json;

namespace WinMint.Orchestrator;

/// <summary>
/// Host helper: compose <c>winmint.profile/v1</c> UTF-8 JSON from UI/CLI fields + already-expanded debloat lists.
/// Does not embed preset names (KEEPFLAG: none in Profile). Package ids (when present) live in Profile JSON.
/// </summary>
public static class WizardProfileComposer
{
    /// <summary>Newline-separated package ids: trim lines, drop blanks, preserve order.</summary>
    public static IReadOnlyList<string> ParseIdList(string? multiline) =>
        string.IsNullOrWhiteSpace(multiline)
            ? []
            : multiline.Split(['\r', '\n'], StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);

    public static byte[] ToUtf8Json(
        string username,
        string password,
        bool requireWifiDuringOobe,
        bool dmaEnabled,
        string locale,
        int geoId,
        string timeZoneId,
        bool locationServicesEnabled,
        IReadOnlyList<string> removeProvisionedAppx,
        IReadOnlyList<string>? winget = null,
        IReadOnlyList<string>? wingetNeedsReboot = null,
        IReadOnlyList<string>? scoop = null,
        IReadOnlyList<string>? scoopNeedsReboot = null,
        IReadOnlyList<string>? wsl = null,
        IReadOnlyList<string>? wslNeedsReboot = null,
        IReadOnlyList<string>? removeCapabilities = null,
        IReadOnlyList<string>? disableOptionalFeatures = null)
    {
        winget ??= [];
        wingetNeedsReboot ??= [];
        scoop ??= [];
        scoopNeedsReboot ??= [];
        wsl ??= [];
        wslNeedsReboot ??= [];
        removeCapabilities ??= [];
        disableOptionalFeatures ??= [];

        PackagesDocument? packages = null;
        if (winget.Count > 0 || wingetNeedsReboot.Count > 0
            || scoop.Count > 0 || scoopNeedsReboot.Count > 0
            || wsl.Count > 0 || wslNeedsReboot.Count > 0)
        {
            packages = new PackagesDocument(
                winget.Count == 0 ? null : winget.ToArray(),
                wingetNeedsReboot.Count == 0 ? null : wingetNeedsReboot.ToArray(),
                scoop.Count == 0 ? null : scoop.ToArray(),
                scoopNeedsReboot.Count == 0 ? null : scoopNeedsReboot.ToArray(),
                wsl.Count == 0 ? null : wsl.ToArray(),
                wslNeedsReboot.Count == 0 ? null : wslNeedsReboot.ToArray());
        }

        DebloatDocument? debloat = null;
        if (removeProvisionedAppx.Count > 0 || removeCapabilities.Count > 0 || disableOptionalFeatures.Count > 0)
        {
            debloat = new DebloatDocument(
                removeProvisionedAppx.Count == 0 ? null : removeProvisionedAppx.ToArray(),
                removeCapabilities.Count == 0 ? null : removeCapabilities.ToArray(),
                disableOptionalFeatures.Count == 0 ? null : disableOptionalFeatures.ToArray());
        }

        ProfileDocument doc = new(
            BuildPlan.ProfileSchemaVersion,
            new AccountDocument(
                AccountModeWire.LocalAutoLogon,
                username,
                password,
                requireWifiDuringOobe),
            new DmaDocument(
                dmaEnabled,
                new DmaSettleDocument(locale, geoId, timeZoneId, locationServicesEnabled)),
            debloat,
            packages);

        return Encoding.UTF8.GetBytes(
            JsonSerializer.Serialize(doc, BuildPlanJsonContext.Default.ProfileDocument));
    }
}
