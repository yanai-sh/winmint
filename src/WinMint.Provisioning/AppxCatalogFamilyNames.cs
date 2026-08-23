namespace WinMint.Provisioning;

/// <summary>
/// Catalog id → Package Family Name for FirstLogon Deprovisioned hive stamps when the
/// package is already absent (offline remove). Microsoft documents creating
/// <c>AppxAllUserStore\Deprovisioned\&lt;PFN&gt;</c> keys manually for FU survival
/// (<see href="https://learn.microsoft.com/en-us/windows/application-management/remove-provisioned-apps-during-update"/>).
/// </summary>
internal static class AppxCatalogFamilyNames
{
    /// <summary>Inbox Microsoft Store publisher id used by most first-party provisioned families.</summary>
    public const string MicrosoftStorePublisherId = "8wekyb3d8bbwe";

    private static readonly Dictionary<string, string> Exceptions = new(StringComparer.OrdinalIgnoreCase)
    {
        // Clipchamp uses a non-Store publisher id on current Win11 media.
        ["Clipchamp.Clipchamp"] = "Clipchamp.Clipchamp_yxz26nhyzhsrt",
        ["5319275A.WhatsAppDesktop"] = "5319275A.WhatsAppDesktop_cv1g1gvanyjgm",
    };

    /// <summary>Resolve PFN for a Profile catalog id when live inventory has no hit.</summary>
    public static string Resolve(string catalogId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(catalogId);
        if (Exceptions.TryGetValue(catalogId.Trim(), out string? exact))
        {
            return exact;
        }

        return $"{catalogId.Trim()}_{MicrosoftStorePublisherId}";
    }
}
