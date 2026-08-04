namespace WinMint.Orchestrator;

/// <summary>
/// Host-side named presets that expand to <c>removeProvisionedAppx</c> catalog ids.
/// Preset names never appear in Profile JSON ([KEEPFLAG] / ADR-005).
/// </summary>
public static class KeepFlagPresets
{
    public const string Empty = "empty";
    public const string Acceptance = "acceptance";

    /// <summary>Pinned acceptance remove-list (samples/acceptance.profile.json / ticket 14).</summary>
    private static readonly string[] AcceptanceIds =
    [
        "Microsoft.BingNews",
        "Microsoft.BingWeather",
    ];

    public static Result<IReadOnlyList<string>, PresetFailure> TryExpand(string name)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            return Result.Fail<IReadOnlyList<string>, PresetFailure>(
                new PresetFailure("keepflag.preset.unknown", "Preset name is required."));
        }

        string key = name.Trim();
        if (string.Equals(key, Empty, StringComparison.OrdinalIgnoreCase))
        {
            return Result.Ok<IReadOnlyList<string>, PresetFailure>([]);
        }

        if (string.Equals(key, Acceptance, StringComparison.OrdinalIgnoreCase))
        {
            // Catalog ⊆ check — fail closed if pin drifts out of ProvisionedAppxCatalog.
            foreach (string id in AcceptanceIds)
            {
                if (!ProvisionedAppxCatalog.Contains(id))
                {
                    return Result.Fail<IReadOnlyList<string>, PresetFailure>(
                        new PresetFailure(
                            "keepflag.preset.catalog",
                            $"Acceptance preset id '{id}' is not in the shipped provisioned AppX catalog."));
                }
            }

            return Result.Ok<IReadOnlyList<string>, PresetFailure>(AcceptanceIds);
        }

        return Result.Fail<IReadOnlyList<string>, PresetFailure>(
            new PresetFailure("keepflag.preset.unknown", $"Unknown keep-flag preset '{key}'."));
    }
}

public sealed record PresetFailure(string Code, string Message);
