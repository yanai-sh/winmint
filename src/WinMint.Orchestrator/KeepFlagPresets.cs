namespace WinMint.Orchestrator;

/// <summary>
/// Host-side named presets that expand to debloat remove-lists.
/// Preset names never appear in Profile JSON ([KEEPFLAG] / ADR-005).
/// </summary>
public static class KeepFlagPresets
{
    public const string Empty = "empty";
    public const string Acceptance = "acceptance";

    /// <summary>Pinned acceptance AppX remove-list (samples/acceptance.profile.json / ticket 14).</summary>
    private static readonly string[] AcceptanceAppx =
    [
        "Microsoft.BingNews",
        "Microsoft.BingWeather",
    ];

    /// <summary>Thin acceptance capability pins (ticket 19/20 / ticket 25).</summary>
    private static readonly string[] AcceptanceCapabilities =
    [
        "App.StepsRecorder~~~~0.0.1.0",
        "WMIC~~~~",
    ];

    /// <summary>Thin acceptance optional-feature pins (ticket 19/20 / ticket 25).</summary>
    private static readonly string[] AcceptanceFeatures =
    [
        "WorkFolders-Client",
    ];

    public static Result<KeepFlagExpansion, PresetFailure> TryExpand(string name)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            return Result.Fail<KeepFlagExpansion, PresetFailure>(
                new PresetFailure("keepflag.preset.unknown", "Preset name is required."));
        }

        string key = name.Trim();
        if (string.Equals(key, Empty, StringComparison.OrdinalIgnoreCase))
        {
            return Result.Ok<KeepFlagExpansion, PresetFailure>(KeepFlagExpansion.Empty);
        }

        if (string.Equals(key, Acceptance, StringComparison.OrdinalIgnoreCase))
        {
            foreach (string id in AcceptanceAppx)
            {
                if (!ProvisionedAppxCatalog.Contains(id))
                {
                    return Result.Fail<KeepFlagExpansion, PresetFailure>(
                        new PresetFailure(
                            "keepflag.preset.catalog",
                            $"Acceptance preset id '{id}' is not in the shipped provisioned AppX catalog."));
                }
            }

            foreach (string id in AcceptanceCapabilities)
            {
                if (!CapabilityCatalog.Contains(id))
                {
                    return Result.Fail<KeepFlagExpansion, PresetFailure>(
                        new PresetFailure(
                            "keepflag.preset.catalog",
                            $"Acceptance preset capability '{id}' is not in the shipped capability catalog."));
                }
            }

            foreach (string id in AcceptanceFeatures)
            {
                if (!OptionalFeatureCatalog.Contains(id))
                {
                    return Result.Fail<KeepFlagExpansion, PresetFailure>(
                        new PresetFailure(
                            "keepflag.preset.catalog",
                            $"Acceptance preset feature '{id}' is not in the shipped optional-feature catalog."));
                }
            }

            return Result.Ok<KeepFlagExpansion, PresetFailure>(
                new KeepFlagExpansion(AcceptanceAppx, AcceptanceCapabilities, AcceptanceFeatures));
        }

        return Result.Fail<KeepFlagExpansion, PresetFailure>(
            new PresetFailure("keepflag.preset.unknown", $"Unknown keep-flag preset '{key}'."));
    }
}

/// <summary>Host-expanded debloat lists (never serialized as a preset name).</summary>
public sealed record KeepFlagExpansion(
    IReadOnlyList<string> RemoveProvisionedAppx,
    IReadOnlyList<string> RemoveCapabilities,
    IReadOnlyList<string> DisableOptionalFeatures)
{
    public static KeepFlagExpansion Empty { get; } = new([], [], []);
}

public sealed record PresetFailure(string Code, string Message);
